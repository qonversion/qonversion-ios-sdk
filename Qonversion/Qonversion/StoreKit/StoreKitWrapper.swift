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
    
    let delegate: StoreKitWrapperDelegate?
    
    init(delegate: StoreKitWrapperDelegate? = nil) {
        self.delegate = delegate
    }
    
    func products(for ids:[String]) async throws -> [Product] {
        let products: [Product] = try await Product.products(for: ids)
        
        return products
    }
    
    func currentEntitlements() async -> [Transaction] {
        return await fetchTransactions(for: Transaction.currentEntitlements)
    }
    
    func restore() async throws {
        return try await AppStore.sync()
    }
    
    func fetchAll() async -> [Transaction] {
        return await fetchTransactions(for: Transaction.all)
    }
    
    func fetchUnfinished() async -> [Transaction] {
        return await fetchTransactions(for: Transaction.unfinished)
    }
    
    func finish(transaction: Transaction) async {
        await transaction.finish()
    }
    
    func purchase(product: Product) async throws -> Transaction {
        let result: Product.PurchaseResult = try await product.purchase()
        
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                return transaction
            case .unverified(let transaction, let verificationError):
                #warning("throw error here using verification error")
                throw QonversionError(type: .critical)
            }
        case .userCancelled:
            #warning("update error here")
            throw QonversionError(type: .critical)
        @unknown default:
            #warning("update error here")
            throw QonversionError(type: .critical)
        }
    }
    
    func subscribe() async -> [Transaction] {
        return await fetchTransactions(for: Transaction.updates)
    }
    
    @available(iOS 16.4, *)
    func subscribeToPromoPurchases() {
        Task.detached {
            for await purchaseIntent in PurchaseIntent.intents {
                self.delegate?.promoPurchaseIntent(product: purchaseIntent.product)
            }
        }
    }
    
        
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }
    
    private func fetchTransactions(for type: Transaction.Transactions) async -> [Transaction] {
      var transasctions: [Transaction] = []
      for await transaction in type {
        switch transaction {
        case .verified(let verifiedTransaction):
          transasctions.append(verifiedTransaction)
        default:
          break
        }
      }
      
      return transasctions
    }
    
}
