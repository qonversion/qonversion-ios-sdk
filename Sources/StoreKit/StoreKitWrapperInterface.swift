//
//  StoreKitWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

protocol StoreKitWrapperInterface: AnyObject, Sendable {

    /// The receiver of promoted-purchase intents. Weak on implementations —
    /// the delegate (the facade) owns the wrapper.
    var delegate: StoreKitWrapperDelegate? { get set }

    func purchase(product: StoreKit.Product, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction
    
    func products(for ids:[String]) async throws -> [StoreKit.Product]
    
    func currentEntitlements() async -> [Qonversion.Transaction]

    /// Syncs with the App Store and returns the restored transactions.
    func restore() async throws -> [Qonversion.Transaction]

    func fetchAll() async -> [Qonversion.Transaction]

    func fetchUnfinished() async -> [Qonversion.Transaction]

    func finish(_ transaction: Qonversion.Transaction) async

    /// A long-lived stream of verified out-of-band transaction updates
    /// (renewals, refunds, Ask to Buy approvals, purchases on other devices).
    func transactionUpdates() -> AsyncStream<Qonversion.Transaction>

    /// Starts observing App Store promoted-purchase intents; they are
    /// delivered to the wrapper delegate.
    @available(iOS 16.4, macOS 14.4, *)
    func subscribeToPromoPurchases()

    func unsubscribeFromPromoPurchases()
        
    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, visionOS 1.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    #endif
}
