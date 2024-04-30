//
//  PurchasesManagerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.04.2024.
//

import Foundation

protocol PurchasesManagerInterface {
    
    func entitlements() async throws -> [Qonversion.Entitlement]
    
}
