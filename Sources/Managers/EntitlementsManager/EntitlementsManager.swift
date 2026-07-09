//
//  EntitlementsManager.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case entitlementsKey = "qonversion.keys.entitlements"
    case entitlementsTimestampKey = "qonversion.keys.entitlementsTimestamp"
}

// @unchecked: stateless — every dependency is thread-safe on its own.
final class EntitlementsManager: EntitlementsManagerInterface, @unchecked Sendable {

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
        let calculated = EntitlementsCalculator.calculate(
            transactions: transactions,
            products: productsDataSource.cachedProducts(),
            mapping: productsDataSource.cachedProductPermissions() ?? [:]
        )
        let merged = EntitlementsCalculator.merge(calculated, into: cachedEntitlements() ?? [:])
        persist(merged)

        return merged
    }

    func entitlements() async throws -> [String: Qonversion.Entitlement] {
        _ = try await userManager.obtainUser()

        do {
            let list: [Qonversion.Entitlement] = try await entitlementsService.entitlements(userId: userIdProvider.getUserId())
            let entitlements = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            persist(entitlements)

            return entitlements
        } catch {
            guard error.allowsLocalEntitlementsFallback else { throw error }

            // Production fault-tolerance path.
            let transactions: [Qonversion.Transaction] = await storeKitFacade.currentEntitlements()
            return await localFallbackEntitlements(for: transactions)
        }
    }
}

// MARK: - UserChangedObserver

extension EntitlementsManager: UserChangedObserver {

    func userDidChange() {
        localStorage.removeObject(forKey: Constants.entitlementsKey.rawValue)
        localStorage.removeObject(forKey: Constants.entitlementsTimestampKey.rawValue)
    }
}

// MARK: - Private

private extension EntitlementsManager {

    func cachedEntitlements() -> [String: Qonversion.Entitlement]? {
        guard let cached = try? localStorage.object(forKey: Constants.entitlementsKey.rawValue, dataType: [String: Qonversion.Entitlement].self) else {
            return nil
        }

        let timestamp: TimeInterval = localStorage.double(forKey: Constants.entitlementsTimestampKey.rawValue)
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp <= cacheLifetimeSeconds else {
            return nil
        }

        return cached
    }

    func persist(_ entitlements: [String: Qonversion.Entitlement]) {
        do {
            try localStorage.set(entitlements, forKey: Constants.entitlementsKey.rawValue)
            localStorage.set(double: Date().timeIntervalSince1970, forKey: Constants.entitlementsTimestampKey.rawValue)
        } catch {
            logger.error("Failed to persist entitlements: " + error.message)
        }
    }
}
