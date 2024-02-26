//
//  StoreKitWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

@available(iOS 15.0, *)
protocol StoreKitWrapperInterface {
    
    func products(for ids:[String]) async throws -> [Product]
    
    func currentEntitlements() async -> [Transaction]
    
    func restore() async throws
    
    func fetchAll() async -> [Transaction]
    
    func fetchUnfinished() async -> [Transaction]
    
    func finish(transaction: Transaction) async
    
    func subscribe() async -> [Transaction]
        
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    
}
