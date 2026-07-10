//
//  ProductsManagerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation

protocol ProductsManagerInterface {
    
    func products() async throws -> [Qonversion.Product]

    /// Fetches the user's offerings with their products enriched with store
    /// data (best-effort).
    func offerings() async throws -> Qonversion.Offerings

    /// Resolves the user's eligibility for the introductory offers of the
    /// given Qonversion products via StoreKit 2.
    func checkTrialIntroEligibility(productIds: [String]) async throws -> [String: Qonversion.IntroEligibilityStatus]

    /// Fetches the product → permissions mapping and refreshes the persistent
    /// cache on every success; on failure the previously cached mapping stays.
    func loadProductPermissions() async
}
