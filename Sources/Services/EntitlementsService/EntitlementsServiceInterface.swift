//
//  EntitlementsServiceInterface.swift
//  Qonversion
//

import Foundation

protocol EntitlementsServiceInterface {

    /// Loads the user's entitlements from the backend.
    func entitlements(userId: String) async throws -> [Qonversion.Entitlement]
}
