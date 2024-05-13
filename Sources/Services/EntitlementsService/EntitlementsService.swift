//
//  EntitlementsService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.04.2024.
//

import Foundation

final class EntitlementsService: EntitlementsServiceInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let internalConfig: InternalConfig
    private let logger: LoggerWrapper
    
    init(requestProcessor: RequestProcessorInterface, internalConfig: InternalConfig, logger: LoggerWrapper) {
        self.requestProcessor = requestProcessor
        self.internalConfig = internalConfig
        self.logger = logger
    }
    
    func entitlements() async throws -> [Qonversion.Entitlement] {
        let request = Request.getEntitlements(userId: internalConfig.userId)
        do {
            class ResponseType : Decodable {
                let data: [Qonversion.Entitlement]
            }
            
            let response: ResponseType = try await requestProcessor.process(request: request, responseType: ResponseType.self)
            
            return response.data
        } catch {
            let error = QonversionError(type: .entitlementsLoadingFailed, message: nil, error: error)
            logger.error(error.message)
            throw error
        }
    }
    
    func entitlementForTransaction(_ transaction: Qonversion.Transaction) -> Qonversion.Entitlement {
        var expirationDate: Date? = nil
        if #available(iOS 15.0, *) {
            expirationDate = transaction.expirationDate
        };

        let isActive = expirationDate == nil || (expirationDate != nil && expirationDate! >= Date())
        
        let entitlement = Qonversion.Entitlement(
            id: "",
            productId: transaction.productId,
            active: isActive,
            renewState: Qonversion.Entitlement.RenewState.unknown,
            source: Qonversion.Entitlement.Source.appStore,
            startedDate: transaction.purchaseDate ?? Date(),
            expirationDate: expirationDate,
            renewsCount: 0,
            trialStartDate: nil,
            firstPurchaseDate: nil,
            lastPurchaseDate: nil,
            lastActivatedOfferCode: nil,
            grantType: Qonversion.Entitlement.GrantType.purchase, // TODO maybe unknown?
            autoRenewDisableDate: nil,
            transactions: []
        )
        
        return entitlement
    }
    
    func mergeEntitlements(_ existingEntitlements: [Qonversion.Entitlement], _ newEntitlements: [Qonversion.Entitlement]) -> [Qonversion.Entitlement] {
        var resultDict: Dictionary<String, Qonversion.Entitlement> = [:]
        existingEntitlements.forEach { resultDict[$0.id] = $0 }
        
        newEntitlements.forEach {
            resultDict[$0.id] = chooseEntitlementToSave(resultDict[$0.id], $0)
        }
        
        return Array(resultDict.values)
    }
    
    private func chooseEntitlementToSave(_ existingEntitlement: Qonversion.Entitlement?, _ newEntitlement: Qonversion.Entitlement) -> Qonversion.Entitlement {
        guard let existingEntitlement else {
            return newEntitlement
        }
        
        let newEntitlementExpirationTime = newEntitlement.expirationDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
        let existingEntitlementExpirationTime = existingEntitlement.expirationDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
        let doesNewOneExpireLater = newEntitlementExpirationTime > existingEntitlementExpirationTime

        // replace if new permission is active and expires later
        if !existingEntitlement.active || doesNewOneExpireLater {
            return newEntitlement
        } else {
            return existingEntitlement
        }

    }
}
