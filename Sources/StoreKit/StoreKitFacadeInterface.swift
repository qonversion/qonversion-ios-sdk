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
    
    func currentEntitlements() async -> [Qonversion.Transaction]
    
    func restore() async throws -> [Qonversion.Transaction]
    
    func finish(transaction: SKPaymentTransaction)
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func finish(transaction: StoreKit.Transaction) async
    
    func subscribe() async -> [Qonversion.Transaction]
        
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet()
    
    func enrich(products: [Qonversion.Product]) async throws -> [Qonversion.Product]
    
}
