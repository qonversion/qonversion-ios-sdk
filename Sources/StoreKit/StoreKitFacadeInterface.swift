//
//  StoreKitFacadeInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import StoreKit

protocol StoreKitFacadeInterface: Sendable {
    // TODO: replace the remaining wrapper return types with domain models.
    func products(for ids:[String]) async throws -> [StoreProductWrapper]

    /// Buys the store product with the given store id (loading it on demand)
    /// and returns the verified transaction carrying its jws proof.
    func purchase(storeId: String, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction

    func currentEntitlements() async -> [Qonversion.Transaction]

    func restore() async throws -> [Qonversion.Transaction]

    func historicalData() async throws -> [Qonversion.Transaction]

    /// Transactions the store still considers unfinished (not acknowledged by
    /// the app in previous sessions).
    func unfinishedTransactions() async -> [Qonversion.Transaction]

    /// Maps a verified store transaction to the domain transaction carrying
    /// its jws proof; unverified results map to nil.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func map(_ verificationResult: VerificationResult<StoreKit.Transaction>) -> Qonversion.Transaction?

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

extension StoreKitFacadeInterface {

    func purchase(storeId: String) async throws -> Qonversion.Transaction {
        try await purchase(storeId: storeId, options: Qonversion.PurchaseOptions())
    }
}
