//
//  StoreKitWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

protocol StoreKitWrapperInterface: Sendable {
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func purchase(product: StoreKit.Product, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func products(for ids:[String]) async throws -> [StoreKit.Product]
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func currentEntitlements() async -> [Qonversion.Transaction]

    /// Syncs with the App Store and returns the restored transactions.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func restore() async throws -> [Qonversion.Transaction]

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func fetchAll() async -> [Qonversion.Transaction]

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func fetchUnfinished() async -> [Qonversion.Transaction]

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func finish(_ transaction: Qonversion.Transaction) async

    /// A long-lived stream of verified out-of-band transaction updates
    /// (renewals, refunds, Ask to Buy approvals, purchases on other devices).
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func transactionUpdates() -> AsyncStream<Qonversion.Transaction>

    /// Starts observing App Store promoted-purchase intents; they are
    /// delivered to the wrapper delegate.
    @available(iOS 16.4, macOS 14.4, *)
    func subscribeToPromoPurchases()
        
    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, visionOS 1.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    #endif
}
