//
//  PurchasesManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.04.2024.
//

import Foundation

fileprivate enum Constants: String {
    case entitlementsKey = "qonversion.keys.entitlements"
}

final class PurchasesManager: PurchasesManagerInterface {
    
    private let entitlementsService: EntitlementsServiceInterface
    private let storeKitFacade: StoreKitFacadeInterface
    private let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper
    
    init(entitlementsService: EntitlementsServiceInterface, storeKitFacade: StoreKitFacadeInterface, localStorage: LocalStorageInterface, logger: LoggerWrapper) {
        self.entitlementsService = entitlementsService
        self.storeKitFacade = storeKitFacade
        self.localStorage = localStorage
        self.logger = logger
    }
    
    func entitlements() async throws -> [Qonversion.Entitlement] {
        do {
            throw QonversionError(type: QonversionErrorType.entitlementsLoadingFailed)
            let entitlements: [Qonversion.Entitlement] = try await entitlementsService.entitlements()

            do {
                try localStorage.set(entitlements, forKey: Constants.entitlementsKey.rawValue)
            } catch {
                logger.warning("Failed to store entitlementes for offline mode: " + error.message)
            }

            return entitlements
        } catch {
            switch error {
            case let entitlementsLoadingError as QonversionError:
                if entitlementsLoadingError.type != .entitlementsLoadingFailed {
                    fallthrough
                }
                
                logger.error("Entitlements loading failed with error: " + entitlementsLoadingError.message)
                
                // Try to grant entitlements using StoreKit
                var storeKitEntitlements: [Qonversion.Entitlement] = []
                do {
                    let transactions = try await storeKitFacade.currentEntitlements() // TODO what will happen if no network if method doesn't throw errors?
                    storeKitEntitlements = transactions.map { entitlementsService.entitlementForTransaction($0) }
                } catch {
                    logger.error("Checking StoreKit entitlements failed with error: " + error.message)
                }

                // Merge StoreKit entitlements with cached ones if any exists
                do {
                    guard let cachedEntitlements: [Qonversion.Entitlement] = try cachedEntitlements() else {
                        logger.warning("No cached entitlements exist.")
                        throw entitlementsLoadingError
                    }

                    let resultEntitlements = entitlementsService.mergeEntitlements(storeKitEntitlements, cachedEntitlements)
                    logger.warning("Returning cached entitlements.")
                    // TODO check cacheLifetime?
                    return resultEntitlements
                } catch {
                    logger.error("Loading cached entitlements also failed with error: " + error.message)
                    throw entitlementsLoadingError
                }
            default:
                throw error
            }
        }
    }
    
    private func cachedEntitlements() throws -> [Qonversion.Entitlement]? {
        return try localStorage.object(forKey: Constants.entitlementsKey.rawValue, dataType: [Qonversion.Entitlement].self)
    }
}
