//
//  EntitlementsManager.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case entitlementsKey = "qonversion.keys.entitlements"
    case entitlementsTimestampKey = "qonversion.keys.entitlementsTimestamp"
}

// TODO: make configurable via Configuration.entitlementsCacheLifetime (config step).
fileprivate let cacheLifetimeSeconds: TimeInterval = 30 * 24 * 60 * 60

final class EntitlementsManager: EntitlementsManagerInterface {

    private let entitlementsService: EntitlementsServiceInterface
    private let storeKitFacade: StoreKitFacadeInterface
    private let productsManager: ProductsManagerInterface
    private let userManager: UserManagerInterface
    private let userIdProvider: UserIdProvider
    private let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper

    init(
        entitlementsService: EntitlementsServiceInterface,
        storeKitFacade: StoreKitFacadeInterface,
        productsManager: ProductsManagerInterface,
        userManager: UserManagerInterface,
        userIdProvider: UserIdProvider,
        localStorage: LocalStorageInterface,
        logger: LoggerWrapper
    ) {
        self.entitlementsService = entitlementsService
        self.storeKitFacade = storeKitFacade
        self.productsManager = productsManager
        self.userManager = userManager
        self.userIdProvider = userIdProvider
        self.localStorage = localStorage
        self.logger = logger
    }

    func entitlements() async throws -> [String: Qonversion.Entitlement] {
        _ = try await userManager.obtainUser()

        do {
            let list = try await entitlementsService.entitlements(userId: userIdProvider.getUserId())
            let entitlements = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            persist(entitlements)

            return entitlements
        } catch {
            guard isLocalCalculationEligible(error) else { throw error }

            // Production fault-tolerance path: calculate entitlements locally
            // from the StoreKit transactions and the cached mapping, merge on
            // top of the cached entitlements and persist to the same cache.
            let transactions = await storeKitFacade.currentEntitlements()
            let calculated = EntitlementsCalculator.calculate(
                transactions: transactions,
                products: productsManager.cachedProducts(),
                mapping: productsManager.cachedProductPermissions() ?? [:]
            )
            let merged = EntitlementsCalculator.merge(calculated, into: cachedEntitlements() ?? [:])
            persist(merged)

            return merged
        }
    }
}

// MARK: - Private

private extension EntitlementsManager {

    /// Production rule: local calculation only for server (5xx) and
    /// connection errors — never for validation or auth failures.
    func isLocalCalculationEligible(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let qonversionError = error as? QonversionError else { return false }
        if qonversionError.type == .internal { return true }
        if let underlying = qonversionError.error {
            return isLocalCalculationEligible(underlying)
        }
        return false
    }

    func cachedEntitlements() -> [String: Qonversion.Entitlement]? {
        guard let cached = try? localStorage.object(forKey: Constants.entitlementsKey.rawValue, dataType: [String: Qonversion.Entitlement].self) else {
            return nil
        }

        let timestamp = localStorage.double(forKey: Constants.entitlementsTimestampKey.rawValue)
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
