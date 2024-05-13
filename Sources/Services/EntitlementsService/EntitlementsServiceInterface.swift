//
//  EntitlementsServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.04.2024.
//

import Foundation

protocol EntitlementsServiceInterface {
    
    func entitlements() async throws -> [Qonversion.Entitlement]

    func entitlementForTransaction(_ transaction: Qonversion.Transaction) -> Qonversion.Entitlement
    
    func mergeEntitlements(_ existingEntitlements: [Qonversion.Entitlement], _ newEntitlements: [Qonversion.Entitlement]) -> [Qonversion.Entitlement]
}
