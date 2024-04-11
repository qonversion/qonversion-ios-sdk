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
    
    func products(for ids:[String]) async throws -> [StoreKit.Product] {
        let products: [StoreKit.Product] = try await Product.products(for: ids)
        
        return products
    }
    
    func currentEntitlements() async -> [StoreKit.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.currentEntitlements)
    }
    
    func restore() async throws {
        return try await AppStore.sync()
    }
    
    func fetchAll() async -> [StoreKit.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.all)
    }
    
    func fetchUnfinished() async -> [StoreKit.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.unfinished)
    }
    
    func finish(transaction: StoreKit.Transaction) async {
        await transaction.finish()
    }
    
    func purchase(product: Product) async throws -> StoreKit.Transaction {
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
    
    func subscribe() async -> [StoreKit.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.updates)
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
    
    private func fetchTransactions(for type: StoreKit.Transaction.Transactions) async -> [StoreKit.Transaction] {
        var transasctions: [StoreKit.Transaction] = []
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

