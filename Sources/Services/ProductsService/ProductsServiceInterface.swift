//
//  ProductsServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2024.
//

import Foundation

protocol ProductsServiceInterface {
    
    func products() async throws -> [Qonversion.Product]

    /// Loads the user's offerings with full embedded products in the
    /// paywall order.
    func offerings(userId: String) async throws -> [Qonversion.Offering]

    /// Loads the product → permissions mapping used for local entitlements
    /// calculation when the backend is unreachable.
    func productPermissions() async throws -> [String: [String]]
}
