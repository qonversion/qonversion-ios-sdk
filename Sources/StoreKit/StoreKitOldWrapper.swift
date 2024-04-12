//
//  StoreKitOldWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import Foundation
import StoreKit

class StoreKitOldWrapper: NSObject, StoreKitOldWrapperInterface {
    
    let delegate: StoreKitOldWrapperDelegate
    let paymentQueue: SKPaymentQueue
    
    var productsRequest: SKProductsRequest?
    var productsCompletions: [SKProductsRequest: StoreKitOldProductsCompletion] = [:]
    var purchaseCompletions: [SKPayment: StoreKitOldTransactionsCompletion] = [:]
    var restoreCompletions: [StoreKitOldTransactionsCompletion] = []
    
    init(delegate: StoreKitOldWrapperDelegate, paymentQueue: SKPaymentQueue) {
        self.delegate = delegate
        self.paymentQueue = paymentQueue
        
        super.init()
        
        paymentQueue.add(self)
    }
    
    func products(for ids:[String], completion: @escaping  StoreKitOldProductsCompletion) {
        let request = SKProductsRequest.init(productIdentifiers: Set(ids))
        request.delegate = self
        request.start()
        
        productsRequest = request
        productsCompletions[request] = completion
    }
    
    func restore(with completion: @escaping StoreKitOldTransactionsCompletion) {
        defer {
            restoreCompletions.append(completion)
        }
        
        if restoreCompletions.count > 0 {
            return
        }
        paymentQueue.restoreCompletedTransactions()
    }
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {
        paymentQueue.presentCodeRedemptionSheet()
    }
    
    func purchase(product: SKProduct, completion: @escaping StoreKitOldTransactionsCompletion) {
        let payment = SKPayment(product: product)
        paymentQueue.add(payment)
        purchaseCompletions[payment] = completion
    }
    
    func finish(transaction: SKPaymentTransaction) {
        guard transaction.transactionState != .purchasing else { return }
        
        paymentQueue.finishTransaction(transaction)
    }
}

// MARK: - SKPaymentTransactionObserver

extension StoreKitOldWrapper: SKPaymentTransactionObserver {
 
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        let restoredTransactions: [SKPaymentTransaction] = transactions.filter { $0.transactionState == .restored }
        if restoredTransactions.count > 0, restoreCompletions.count > 0  {
            fireRestoreCompletions(with: restoredTransactions)
        }
        
        firePurchaseCompletions(with: transactions)
        
        if purchaseCompletions.isEmpty {
            delegate.updated(transactions: transactions)
        }
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        guard restoreCompletions.count > 0 else {
            return delegate.handle(restoreTransactionsError: error)
        }
        
        fireRestoreCompletions(with: [], error: error)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return delegate.shouldAdd(storePayment: payment, for: product)
    }
    
}

// MARK: - SKProductsRequestDelegate

extension StoreKitOldWrapper: SKProductsRequestDelegate {
   
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        guard let completion: StoreKitOldProductsCompletion = productsCompletions[request] else {
            return delegate.handle(productsResponse: response)
        }
        
        completion(response, nil)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        guard request is SKProductsRequest else { return }
        
        delegate.handle(productsRequestError: error)
    }
    
}

// MARK: - Private

extension StoreKitOldWrapper {
    
    func fireRestoreCompletions(with transactions: [SKPaymentTransaction], error: Error? = nil) {
        restoreCompletions.forEach { $0(transactions, error) }
        restoreCompletions.removeAll()
    }
    
    func firePurchaseCompletions(with transactions: [SKPaymentTransaction]) {
        let completionsCopy: [SKPayment: StoreKitOldTransactionsCompletion] = purchaseCompletions
        completionsCopy.keys.forEach { payment in
            if let _: SKPaymentTransaction = transactions.first(where: { $0.payment == payment }),
               let completion: StoreKitOldTransactionsCompletion = completionsCopy[payment] {
                completion(transactions, nil)
                purchaseCompletions[payment] = nil
            }
        }
    }
}