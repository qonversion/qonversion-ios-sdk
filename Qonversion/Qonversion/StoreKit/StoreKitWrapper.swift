//
//  StoreKitWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

@available(iOS 15.0, *)
final class StoreKitWrapper: StoreKitWrapperInterface {
    
    var allTransactions: [Transaction] = []
    
    func products(for ids:[String]) async throws -> [Product] {
        let products: [Product] = try await Product.products(for: ids)
        
        return products
    }
    
    func currentEntitlements() -> Transaction.Transactions {
        return Transaction.currentEntitlements
    }
    
    func restore() async throws {
        return try await AppStore.sync()
    }
    
    func allTransactions() async -> Transaction.Transactions? {
        Task {
            for await transaction in Transaction.all {
                switch transaction {
                case .verified(let verifiedTransaction):
                    allTransactions.append(verifiedTransaction)
                default:
                    break
                }
            }
            
            return allTransactions
        }
    }
    
    func finish(transaction: Transaction) async {
        await transaction.finish()
    }
    
    func subscribe() async {
        for await update in StoreKit.Transaction.updates {
            if let transaction = try? update.payloadValue {
                
            }
        }
    }
    
    
        
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }
    
}
