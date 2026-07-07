//
//  EntitlementsServiceInterface.swift
//  Qonversion
//

import Foundation

protocol EntitlementsServiceInterface {

    /// Loads the user's entitlements: GET v3/users/{uid}/entitlements.
    func entitlements(userId: String) async throws -> [Qonversion.Entitlement]
}
