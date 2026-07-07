//
//  ProductsDataSource.swift
//  Qonversion
//

import Foundation

/// Read-only source of the session data the local entitlements calculation
/// needs. Consumers can read the caches but cannot trigger loading.
protocol ProductsDataSource {

    /// Products loaded during this session.
    func cachedProducts() -> [Qonversion.Product]

    /// The last known product → permissions mapping (memory, then persistent cache).
    func cachedProductPermissions() -> [String: [String]]?
}
