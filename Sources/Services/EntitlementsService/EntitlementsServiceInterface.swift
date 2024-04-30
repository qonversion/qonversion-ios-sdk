//
//  EntitlementsServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.04.2024.
//

import Foundation

protocol EntitlementsServiceInterface {
    
    func entitlements() async throws -> [Qonversion.Entitlement]
}
