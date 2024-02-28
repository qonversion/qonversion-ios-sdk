//
//  StoreKitFacadeInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import StoreKit

protocol StoreKitFacadeInterface {
    
    func products(for ids:[String]) async throws -> [String]
    
    func currentEntitlements() async -> [String]
    
    func restore() async throws
    
//    func fetchAll() async -> [Transaction]
    
    func historicalData() async -> [String]
    
    func finish(transaction: SKPaymentTransaction)
    
    @available(iOS 15.0, *)
    func finish(transaction: Transaction)
    
    func subscribe() async -> [String]
        
//    @available(iOS 16.0, *)
//    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    
}
