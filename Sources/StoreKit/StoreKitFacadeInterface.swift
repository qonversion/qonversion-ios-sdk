//
//  StoreKitFacadeInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import StoreKit

protocol StoreKitFacadeInterface {
    #warning("replace all return types")
    func products(for ids:[String]) async throws -> [StoreProductWrapper]

    /// Buys the store product with the given store id (loading it on demand)
    /// and returns the verified transaction carrying its jws proof.
    func purchase(storeId: String) async throws -> Qonversion.Transaction

    func currentEntitlements() async -> [Qonversion.Transaction]

    func restore() async throws -> [Qonversion.Transaction]

    func historicalData() async throws -> [Qonversion.Transaction]

    /// Finishes the transaction with the store it came from. Never called
    /// automatically by the SDK for observed updates.
    func finish(_ transaction: Qonversion.Transaction) async

    /// Starts the long-lived observation of out-of-band transaction updates;
    /// verified transactions are delivered to the facade delegate.
    func startObservingTransactionUpdates()

    func stopObservingTransactionUpdates()
        
    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    #endif

    #if os(iOS) || os(visionOS)
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet()
    #endif
}
