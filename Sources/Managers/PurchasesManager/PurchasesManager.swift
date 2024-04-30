//
//  PurchasesManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.04.2024.
//

import Foundation

final class PurchasesManager: PurchasesManagerInterface {
    
    let entitlementsService: EntitlementsServiceInterface
    let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper
    
    init(entitlementsService: EntitlementsServiceInterface, localStorage: LocalStorageInterface, logger: LoggerWrapper) {
        self.entitlementsService = entitlementsService
        self.localStorage = localStorage
        self.logger = logger
    }
    
    func entitlements() async throws -> [Qonversion.Entitlement] {
        let entitlements: [Qonversion.Entitlement] = try await entitlementsService.entitlements()
        
        return entitlements
    }
    
}
