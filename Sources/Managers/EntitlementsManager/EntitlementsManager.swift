//
//  EntitlementsManager.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case entitlementsKey = "qonversion.keys.entitlements"
    case entitlementsTimestampKey = "qonversion.keys.entitlementsTimestamp"
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
        // Snapshotted before the first suspension: a user switch landing while
        // the request is in flight must not let the previous user's
        // entitlements reach the new user's cache.
        let generation: Int = currentGeneration()

        do {
            _ = try await userManager.obtainUser()

            let list: [Qonversion.Entitlement] = try await entitlementsService.entitlements(userId: userIdProvider.getUserId())
            let entitlements = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            persist(entitlements, ifGenerationIs: generation)

            return entitlements
        } catch {
            // Production fault tolerance: ANY launch failure — including the
            // user gate, auth and rate-limit errors — is answered from the
            // cache plus the local StoreKit calculation. The error surfaces
            // only when there is nothing at all to serve.
            let transactions: [Qonversion.Transaction] = await storeKitFacade.currentEntitlements()
            let fallback: [String: Qonversion.Entitlement] = localFallbackEntitlements(for: transactions, generation: generation)
            guard !fallback.isEmpty else { throw error }

            return fallback
        }
    }
}

// MARK: - UserChangedObserver

extension EntitlementsManager: UserChangedObserver {

    func userDidChange() {
        lock.lock()
        cacheGeneration += 1
        lock.unlock()

        localStorage.removeObject(forKey: Constants.entitlementsKey.rawValue)
        localStorage.removeObject(forKey: Constants.entitlementsTimestampKey.rawValue)
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
        persist(merged, ifGenerationIs: generation)

        return merged
    }

    func cachedEntitlements() -> [String: Qonversion.Entitlement]? {
        guard let cached = try? localStorage.object(forKey: Constants.entitlementsKey.rawValue, dataType: [String: Qonversion.Entitlement].self) else {
            return nil
        }

        let timestamp: TimeInterval = localStorage.double(forKey: Constants.entitlementsTimestampKey.rawValue)
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

    func persist(_ entitlements: [String: Qonversion.Entitlement], ifGenerationIs generation: Int) {
        lock.lock()
        let isCurrent: Bool = generation == cacheGeneration
        lock.unlock()
        guard isCurrent else { return }

        do {
            try localStorage.set(entitlements, forKey: Constants.entitlementsKey.rawValue)
            localStorage.set(double: Date().timeIntervalSince1970, forKey: Constants.entitlementsTimestampKey.rawValue)
        } catch {
            logger.error("Failed to persist entitlements: " + error.message)
        }
    }
}
