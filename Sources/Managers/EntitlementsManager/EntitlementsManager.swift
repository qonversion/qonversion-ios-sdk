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
        return localFallbackEntitlements(for: transactions, generation: currentGeneration())
    }

    func entitlements() async throws -> [String: Qonversion.Entitlement] {
        return try await resolvedEntitlements().entitlements
    }

    func resolvedEntitlements() async throws -> ResolvedEntitlements {
        // Snapshotted before the first suspension: a user switch landing while
        // the request is in flight must not let the previous user's
        // entitlements reach the new user's cache.
        let generation: Int = currentGeneration()

        do {
            _ = try await userManager.obtainUser()

            let list: [Qonversion.Entitlement] = try await entitlementsService.entitlements(userId: userIdProvider.getUserId())
            let entitlements = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            persist(entitlements, ifGenerationIs: generation, isBackendAnswer: true)

            return ResolvedEntitlements(entitlements: entitlements, source: .backend)
        } catch {
            // Production fault tolerance: ANY launch failure — including the
            // user gate, auth and rate-limit errors — is answered from the
            // cache plus the local StoreKit calculation. The error surfaces
            // only when there is nothing at all to serve.
            let transactions: [Qonversion.Transaction] = await storeKitFacade.currentEntitlements()
            let fallback: [String: Qonversion.Entitlement] = localFallbackEntitlements(for: transactions, generation: generation)
            guard !fallback.isEmpty else { throw error }

            return ResolvedEntitlements(entitlements: fallback, source: .localCalculation)
        }
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

    func localFallbackEntitlements(for transactions: [Qonversion.Transaction], generation: Int) -> [String: Qonversion.Entitlement] {
        let calculated = EntitlementsCalculator.calculate(
            transactions: transactions,
            products: productsDataSource.cachedProducts(),
            mapping: productsDataSource.cachedProductPermissions() ?? [:]
        )
        let merged = EntitlementsCalculator.merge(calculated, into: cachedEntitlements() ?? [:])
        persist(merged, ifGenerationIs: generation, isBackendAnswer: false)

        return merged
    }

    func cachedEntitlements() -> [String: Qonversion.Entitlement]? {
        guard let cached = try? localStorage.object(forKey: Constants.entitlementsKey.rawValue, dataType: [String: Qonversion.Entitlement].self) else {
            return nil
        }

        // The lifetime runs from the last backend answer. An install that has
        // never had one holds locally calculated data only, which carries its
        // own expiration and is filtered below — there the write timestamp is
        // the best reference available.
        let backendTimestamp: TimeInterval = localStorage.double(forKey: Constants.backendTimestampKey.rawValue)
        let timestamp: TimeInterval = backendTimestamp > 0 ? backendTimestamp : localStorage.double(forKey: Constants.entitlementsTimestampKey.rawValue)
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp <= cacheLifetimeSeconds else {
            return nil
        }

        // Production rule: an entry that claims active past its own expiration
        // is stale — serving it would report access the user no longer has.
        let now = Date()
        return cached.filter { _, entitlement in
            guard entitlement.active, let expirationDate: Date = entitlement.expirationDate else { return true }

            return expirationDate >= now
        }
    }

    /// The generation check and the write are one step: a user switch landing
    /// between them would resurrect the previous user's entitlements.
    func persist(_ entitlements: [String: Qonversion.Entitlement], ifGenerationIs generation: Int, isBackendAnswer: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return }

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
    }
}
