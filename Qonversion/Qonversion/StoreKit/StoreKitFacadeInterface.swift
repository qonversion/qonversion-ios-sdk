//
//  StoreKitFacadeInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import StoreKit

protocol StoreKitFacadeInterface {
    #warning("replace all return types")
    func products(for ids:[String]) async throws -> [String]
    
    func currentEntitlements() async -> [Transaction]
    
    func restore() async throws -> [Transaction]
    
    func finish(transaction: SKPaymentTransaction)
    
    @available(iOS 15.0, *)
    func finish(transaction: StoreKit.Transaction) async
    
    func subscribe() async -> [Transaction]
        
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet()
    
}
