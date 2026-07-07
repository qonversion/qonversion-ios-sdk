//
//  ProductsManagerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation

protocol ProductsManagerInterface {
    
    func products() async throws -> [Qonversion.Product]

    /// Fetches the product → permissions mapping and refreshes the persistent
    /// cache on every success; on failure the previously cached mapping stays.
    func loadProductPermissions() async

    /// The last known mapping: in-memory, falling back to the persistent cache.
    func cachedProductPermissions() -> [String: [String]]?

    /// Products loaded during this session (used for local entitlements calculation).
    func cachedProducts() -> [Qonversion.Product]
}
