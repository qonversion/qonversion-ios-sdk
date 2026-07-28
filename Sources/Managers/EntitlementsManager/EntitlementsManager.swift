//
//  EntitlementsManager.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case entitlementsKey = "qonversion.keys.entitlements"
    case entitlementsTimestampKey = "qonversion.keys.entitlementsTimestamp"
    // When the backend last answered. The local fallback must NOT touch this
    // key, or a permanently failing backend keeps a lapsed user premium forever.
    case backendTimestampKey = "qonversion.keys.entitlementsBackendTimestamp"
}

// @unchecked: the generation counter is lock-guarded, every dependency is thread-safe.
final class EntitlementsManager: EntitlementsManagerInterface, @unchecked Sendable {

    private let lock = NSLock()

    /// Bumped on every user switch: a fetch that started for the previous user
    /// must not persist its (stale) entitlements for the new one.
    private var cacheGeneration = 0

    /// The resolution in flight, joined by every concurrent caller: N gating
    /// checks must cost one request.
    private var _resolutionTask: Task<ResolvedEntitlements, Error>?

    /// Owner of the resolution slot, so a run that ends after the slot changed
    /// hands releases nothing. Monotonic, issued under `lock`.
    private var resolutionTicket: UInt64 = 0

    /// How long a BACKEND answer is served without asking again (ObjC parity:
    /// QNUtils.m:18, QNProductCenterManager.m:594).
    static var freshCacheLifetime: TimeInterval { 300 }

    private let entitlementsService: EntitlementsServiceInterface
    private let storeKitFacade: StoreKitFacadeInterface
    private let productsDataSource: ProductsDataSource
    private let userManager: UserManagerInterface
    private let userIdProvider: UserIdProvider
    private let localStorage: LocalStorageInterface
    private let cacheLifetimeSeconds: TimeInterval
    private let logger: LoggerWrapper

    init(
        entitlementsService: EntitlementsServiceInterface,
        storeKitFacade: StoreKitFacadeInterface,
        productsDataSource: ProductsDataSource,
        userManager: UserManagerInterface,
        userIdProvider: UserIdProvider,
        localStorage: LocalStorageInterface,
        cacheLifetime: TimeInterval,
        logger: LoggerWrapper
    ) {
        self.entitlementsService = entitlementsService
        self.storeKitFacade = storeKitFacade
        self.productsDataSource = productsDataSource
        self.userManager = userManager
        self.userIdProvider = userIdProvider
        self.localStorage = localStorage
        self.cacheLifetimeSeconds = cacheLifetime
        self.logger = logger
    }

    func localFallbackEntitlements(for transactions: [Qonversion.Transaction]) async -> [String: Qonversion.Entitlement] {
        return localFallbackEntitlements(for: transactions, generation: currentGeneration()) ?? [:]
    }

    func entitlements() async throws -> [String: Qonversion.Entitlement] {
        return try await resolvedEntitlements().entitlements
    }

    func invalidateFreshBackendCache() {
        lock.lock()
        defer { lock.unlock() }

        let backendTimestamp: TimeInterval = localStorage.double(forKey: Constants.backendTimestampKey.rawValue)
        guard backendTimestamp > 0 else { return }

        // Expired, not removed: the cache LIFETIME is measured from this same
        // key, and handing that clock to the local fallback — which refreshes
        // its own timestamp on every failure — would keep a lapsed user premium.
        let expired: TimeInterval = Date().timeIntervalSince1970 - Self.freshCacheLifetime - 1
        guard expired < backendTimestamp else { return }

        localStorage.set(double: expired, forKey: Constants.backendTimestampKey.rawValue)
    }

    func resolvedEntitlements() async throws -> ResolvedEntitlements {
        // Inside the fresh window the cache is served as it is — no user gate,
        // no request, so a per-appearance gating check costs nothing.
        if let fresh: [String: Qonversion.Entitlement] = freshBackendEntitlements() {
            return ResolvedEntitlements(entitlements: servable(fresh), source: .backend)
        }

        let task: Task<ResolvedEntitlements, Error> = joinedResolutionTask()

        return try await task.value
    }
}

// MARK: - Private resolution

private extension EntitlementsManager {

    func joinedResolutionTask() -> Task<ResolvedEntitlements, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let inFlight: Task<ResolvedEntitlements, Error> = _resolutionTask {
            return inFlight
        }

        // The run releases the slot itself, and by ticket: userDidChange()
        // empties the slot out of band, so a run must never evict its successor.
        resolutionTicket += 1
        let ticket: UInt64 = resolutionTicket
        let task = Task { [weak self] () throws -> ResolvedEntitlements in
            guard let self else { throw QonversionError(type: .entitlementsLoadingFailed) }
            defer { self.clearResolutionTask(ticket: ticket) }

            return try await self.resolve(attemptsLeft: 1)
        }
        // Written under the lock this call still holds, so a run reaching its
        // defer immediately waits for it.
        _resolutionTask = task

        return task
    }

    func clearResolutionTask(ticket: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard resolutionTicket == ticket else { return }

        _resolutionTask = nil
    }

    /// `attemptsLeft` bounds the re-resolution a user switch triggers.
    func resolve(attemptsLeft: Int) async throws -> ResolvedEntitlements {
        // Snapshotted before the first suspension: a user switch mid-flight
        // must not leak the previous user's entitlements to the new one.
        let generation: Int = currentGeneration()

        do {
            _ = try await userManager.obtainUser()

            let list: [Qonversion.Entitlement] = try await entitlementsService.entitlements(userId: userIdProvider.getUserId())
            let entitlements = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            guard persist(entitlements, ifGenerationIs: generation, isBackendAnswer: true) else {
                return try await resolveForTheNewUser(attemptsLeft: attemptsLeft)
            }

            return ResolvedEntitlements(entitlements: servable(entitlements), source: .backend)
        } catch {
            // Deliberate fault tolerance: ANY failure is answered from cache
            // plus local calculation; the error surfaces only with nothing to serve.
            let transactions: [Qonversion.Transaction] = await storeKitFacade.currentEntitlements()
            // A rejected persist means the user changed mid-run: the merge
            // describes the previous user, so the original failure surfaces instead.
            guard let fallback: [String: Qonversion.Entitlement] = localFallbackEntitlements(for: transactions, generation: generation) else { throw error }
            guard !fallback.isEmpty else { throw error }

            return ResolvedEntitlements(entitlements: fallback, source: .localCalculation)
        }
    }

    func resolveForTheNewUser(attemptsLeft: Int) async throws -> ResolvedEntitlements {
        guard attemptsLeft > 0 else {
            throw QonversionError(type: .entitlementsLoadingFailed, message: "The user changed while the entitlements were loading.")
        }

        return try await resolve(attemptsLeft: attemptsLeft - 1)
    }

    /// The cached BACKEND answer while it is still fresh, unfiltered. nil when
    /// there is none, when it is stale, or when it holds an entitlement active
    /// past its own expiration (ObjC parity: QNProductCenterManager.m:597-605).
    func freshBackendEntitlements() -> [String: Qonversion.Entitlement]? {
        let backendTimestamp: TimeInterval = localStorage.double(forKey: Constants.backendTimestampKey.rawValue)
        guard backendTimestamp > 0, Date().timeIntervalSince1970 - backendTimestamp <= Self.freshCacheLifetime else { return nil }

        guard let stored: [String: Qonversion.Entitlement] = storedEntitlements() else { return nil }

        let now = Date()
        let holdsAnExpiredGrant: Bool = stored.values.contains { entitlement in
            guard entitlement.active, let expirationDate: Date = entitlement.expirationDate else { return false }

            return expirationDate < now
        }
        guard !holdsAnExpiredGrant else { return nil }

        return stored
    }
}

// MARK: - UserChangedObserver

extension EntitlementsManager: UserChangedObserver {

    func userDidChange() {
        // The bump and the wipe are one step: a persist slipping in between
        // would write the previous user's entitlements right back.
        lock.lock()
        defer { lock.unlock() }

        cacheGeneration += 1
        // The resolution in flight belongs to the previous user: the next
        // caller must start its own. The ticket is deliberately left alone —
        // only the next caller taking the slot over revokes the run's claim.
        _resolutionTask = nil
        localStorage.removeObject(forKey: Constants.entitlementsKey.rawValue)
        localStorage.removeObject(forKey: Constants.entitlementsTimestampKey.rawValue)
        localStorage.removeObject(forKey: Constants.backendTimestampKey.rawValue)
    }
}

// MARK: - Private

private extension EntitlementsManager {

    func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cacheGeneration
    }

    /// nil means the persist was rejected by a user change — the result
    /// describes somebody else and must not be served.
    func localFallbackEntitlements(for transactions: [Qonversion.Transaction], generation: Int) -> [String: Qonversion.Entitlement]? {
        let calculated = EntitlementsCalculator.calculate(
            transactions: transactions,
            products: productsDataSource.cachedProducts(),
            mapping: productsDataSource.cachedProductPermissions() ?? [:]
        )
        // Persisted UNFILTERED: the expiry filter decides what is served, never
        // what is kept, or entitlements the SDK cannot regenerate locally
        // (stripe, manual) would be lost the first time the backend is down.
        let merged = EntitlementsCalculator.merge(calculated, into: storedEntitlements() ?? [:])
        guard persist(merged, ifGenerationIs: generation, isBackendAnswer: false) else { return nil }

        return servable(merged)
    }

    /// The persisted entitlements, as they were written. Honors the configured
    /// cache lifetime — past it there is nothing to serve at all.
    func storedEntitlements() -> [String: Qonversion.Entitlement]? {
        guard let cached = try? localStorage.object(forKey: Constants.entitlementsKey.rawValue, dataType: [String: Qonversion.Entitlement].self) else {
            return nil
        }

        // The lifetime runs from the last backend answer; an install that never
        // had one falls back to the write timestamp.
        let backendTimestamp: TimeInterval = localStorage.double(forKey: Constants.backendTimestampKey.rawValue)
        let timestamp: TimeInterval = backendTimestamp > 0 ? backendTimestamp : localStorage.double(forKey: Constants.entitlementsTimestampKey.rawValue)
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp <= cacheLifetimeSeconds else {
            return nil
        }

        return cached
    }

    /// Drops entries claiming active past their own expiration. Applied on the
    /// way OUT only; see localFallbackEntitlements.
    func servable(_ entitlements: [String: Qonversion.Entitlement]) -> [String: Qonversion.Entitlement] {
        let now = Date()

        return entitlements.filter { _, entitlement in
            guard entitlement.active, let expirationDate: Date = entitlement.expirationDate else { return true }

            return expirationDate >= now
        }
    }

    /// The generation check and the write are one step: a user switch between
    /// them would resurrect the previous user's entitlements. false means the
    /// write was refused — the caller must not serve the value.
    @discardableResult
    func persist(_ entitlements: [String: Qonversion.Entitlement], ifGenerationIs generation: Int, isBackendAnswer: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return false }

        do {
            try localStorage.set(entitlements, forKey: Constants.entitlementsKey.rawValue)
            let now: TimeInterval = Date().timeIntervalSince1970
            localStorage.set(double: now, forKey: Constants.entitlementsTimestampKey.rawValue)
            if isBackendAnswer {
                localStorage.set(double: now, forKey: Constants.backendTimestampKey.rawValue)
            }
        } catch {
            logger.error("Failed to persist entitlements: " + error.message)
        }

        return true
    }
}
