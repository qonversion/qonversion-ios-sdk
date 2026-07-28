//
//  EntitlementsManager.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case entitlementsKey = "qonversion.keys.entitlements"
    case entitlementsTimestampKey = "qonversion.keys.entitlementsTimestamp"
    // When the backend last answered. The local fallback persists what it
    // merged but must NOT touch this key: otherwise a permanently failing
    // backend would keep refreshing the cache lifetime and a lapsed user
    // would stay premium forever.
    case backendTimestampKey = "qonversion.keys.entitlementsBackendTimestamp"
}

// @unchecked: the generation counter is lock-guarded, every dependency is
// thread-safe on its own.
final class EntitlementsManager: EntitlementsManagerInterface, @unchecked Sendable {

    // Read by the fetch flows, bumped from the user-change notification thread.
    private let lock = NSLock()

    /// Bumped on every user switch: a fetch that started for the previous user
    /// must not persist its (stale) entitlements for the new one.
    private var cacheGeneration = 0

    /// The resolution currently in flight, joined by every concurrent caller:
    /// gating checks happen on every screen, and N of them must cost one
    /// request, not N.
    private var _resolutionTask: Task<ResolvedEntitlements, Error>?

    /// Names the run that owns the slot, so a run that ends after the slot
    /// changed hands releases nothing. Monotonic, issued under `lock`.
    private var resolutionTicket: UInt64 = 0

    /// How long a BACKEND answer is served without asking again. The ObjC SDK
    /// answered checkEntitlements straight from the cache inside this window
    /// (QNUtils.m:18 — `defaultState ? 60.0 * 5.0 : cacheLifetime`, the
    /// configured entitlementsCacheLifetime only applying once the launch had
    /// failed), and QNProductCenterManager.m:594 is the call site.
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

    func resolvedEntitlements() async throws -> ResolvedEntitlements {
        // A backend answer that is still inside the fresh window is served as
        // it is — no user gate, no request. This is the ObjC behavior and the
        // reason a paywall that checks access on every appearance does not
        // generate a request per appearance.
        if let fresh: [String: Qonversion.Entitlement] = freshBackendEntitlements() {
            return ResolvedEntitlements(entitlements: servable(fresh), source: .backend)
        }

        // Single-flight: N concurrent gating checks share one round trip.
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

        // The run releases the slot as its own last act, before its value
        // becomes observable: clearing it from the caller instead would leave
        // a window where a joining call is answered by a finished run.
        //
        // The clear is by identity, and the ticket is what carries it — a task
        // cannot be captured by the closure that defines it. Identity is
        // required because userDidChange() empties the slot OUT OF BAND while
        // a run is still going: by the time that run ends the slot may already
        // hold the run started for the new user, and wiping it would send the
        // next caller off on a third concurrent resolution.
        resolutionTicket += 1
        let ticket: UInt64 = resolutionTicket
        let task = Task { [weak self] () throws -> ResolvedEntitlements in
            guard let self else { throw QonversionError(type: .entitlementsLoadingFailed) }
            defer { self.clearResolutionTask(ticket: ticket) }

            return try await self.resolve(attemptsLeft: 1)
        }
        // Written under the lock this call still holds, so a run that reaches
        // its defer immediately waits for it.
        _resolutionTask = task

        return task
    }

    func clearResolutionTask(ticket: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        // A later run has taken the slot over — the user switched while this
        // one was in flight, and evicting its successor here is exactly the
        // bug the ticket exists to prevent.
        guard resolutionTicket == ticket else { return }

        _resolutionTask = nil
    }

    /// `attemptsLeft` bounds the re-resolution a user switch triggers: without
    /// it a host switching users in a loop could keep this recursing.
    func resolve(attemptsLeft: Int) async throws -> ResolvedEntitlements {
        // Snapshotted before the first suspension: a user switch landing while
        // the request is in flight must not let the previous user's
        // entitlements reach the new user's cache — or the new user's caller.
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
            // Production fault tolerance: ANY launch failure — including the
            // user gate, auth and rate-limit errors — is answered from the
            // cache plus the local StoreKit calculation. The error surfaces
            // only when there is nothing at all to serve.
            let transactions: [Qonversion.Transaction] = await storeKitFacade.currentEntitlements()
            // A rejected persist means the user changed while this ran: the
            // merge describes the previous user, so it is neither kept nor
            // served. Unlike the backend path there is nothing to re-resolve —
            // the backend is unreachable — so the original failure surfaces
            // and the new user's next call starts clean.
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
    /// there is none, when it is older than the fresh window, or when it
    /// contains an entitlement claiming to be active past its own expiration —
    /// ObjC's second condition (QNProductCenterManager.m:597-605): such a cache
    /// no longer describes reality, so the backend is asked again.
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
        // The bump and the wipe are one step: a persist that passes the
        // generation check in between would write the previous user's
        // entitlements right back.
        lock.lock()
        defer { lock.unlock() }

        cacheGeneration += 1
        // The resolution in flight belongs to the previous user: the next
        // caller must start its own instead of joining it. The ticket is left
        // alone on purpose: the run in flight still owns the empty slot, and
        // only the next caller taking the slot over revokes its claim to it.
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

    /// nil means the persist was rejected because the user changed — the
    /// result describes somebody else and must not be served.
    func localFallbackEntitlements(for transactions: [Qonversion.Transaction], generation: Int) -> [String: Qonversion.Entitlement]? {
        let calculated = EntitlementsCalculator.calculate(
            transactions: transactions,
            products: productsDataSource.cachedProducts(),
            mapping: productsDataSource.cachedProductPermissions() ?? [:]
        )
        // Merged into and persisted UNFILTERED. The expiry filter decides what
        // is served, never what is kept: entitlements the SDK cannot
        // regenerate locally — stripe, manual, anything not backed by an App
        // Store transaction — would otherwise be deleted for good the first
        // time the backend was unreachable, and only a successful backend
        // answer could ever bring them back.
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

        // The lifetime runs from the last backend answer. An install that has
        // never had one holds locally calculated data only, which carries its
        // own expiration and is filtered on read — there the write timestamp
        // is the best reference available.
        let backendTimestamp: TimeInterval = localStorage.double(forKey: Constants.backendTimestampKey.rawValue)
        let timestamp: TimeInterval = backendTimestamp > 0 ? backendTimestamp : localStorage.double(forKey: Constants.entitlementsTimestampKey.rawValue)
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp <= cacheLifetimeSeconds else {
            return nil
        }

        return cached
    }

    /// Production rule: an entry that claims active past its own expiration is
    /// stale — serving it would report access the user no longer has. Applied
    /// on the way OUT only; see localFallbackEntitlements.
    func servable(_ entitlements: [String: Qonversion.Entitlement]) -> [String: Qonversion.Entitlement] {
        let now = Date()

        return entitlements.filter { _, entitlement in
            guard entitlement.active, let expirationDate: Date = entitlement.expirationDate else { return true }

            return expirationDate >= now
        }
    }

    /// The generation check and the write are one step: a user switch landing
    /// between them would resurrect the previous user's entitlements. false
    /// means the write was refused — the caller must not serve the value.
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
