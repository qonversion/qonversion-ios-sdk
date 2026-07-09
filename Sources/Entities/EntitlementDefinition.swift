//
//  EntitlementDefinition.swift
//  Qonversion
//

import Foundation

/// A dashboard-defined entitlement with the products that unlock it. The SDK
/// inverts the list into a product -> entitlements mapping for the local
/// entitlements calculation.
struct EntitlementDefinition: Decodable {

    let id: String
    let productIds: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case productIds = "product_ids"
    }

    init(id: String, productIds: [String]) {
        self.id = id
        self.productIds = productIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        productIds = try container.decodeIfPresent([String].self, forKey: .productIds) ?? []
    }
}
