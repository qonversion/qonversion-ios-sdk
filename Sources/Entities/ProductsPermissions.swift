//
//  ProductsPermissions.swift
//  Qonversion
//

import Foundation

/// The project-level product → permissions mapping used for local
/// entitlements calculation when the backend is unreachable.
struct ProductsPermissions: Decodable {

    /// Qonversion product id → permission ids it unlocks.
    let productsPermissions: [String: [String]]

    private enum CodingKeys: String, CodingKey {
        case productsPermissions = "products_permissions"
    }
}
