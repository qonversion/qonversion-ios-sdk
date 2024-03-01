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
    
    init(delegate: StoreKitOldWrapperDelegate, paymentQueue: SKPaymentQueue) {
        self.delegate = delegate
        self.paymentQueue = paymentQueue
        
        super.init()
        
        paymentQueue.add(self)
    }
    
    func loadProducts(for ids:[String]) {
        let request = SKProductsRequest.init(productIdentifiers: Set(ids))
        request.delegate = self
        request.start()
        
        productsRequest = request
    }
    
    func restore() {
        paymentQueue.restoreCompletedTransactions()
    }
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {
        paymentQueue.presentCodeRedemptionSheet()
    }
    
    func purchase(product: SKProduct) {
        let payment = SKPayment(product: product)
        paymentQueue.add(payment)
    }
    
    func finish(transaction: SKPaymentTransaction) {
        guard transaction.transactionState != .purchasing else { return }
        
        paymentQueue.finishTransaction(transaction)
    }
}

extension StoreKitOldWrapper: SKPaymentTransactionObserver {
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        delegate.updated(transactions: transactions)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        delegate.handle(restoreTransactionsError: error)
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        delegate.handleRestoreFinished()
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return delegate.shouldAdd(storePayment: payment, for: product)
    }
    
}

extension StoreKitOldWrapper: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        delegate.handle(productsResponse: response)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        guard let request = request as? SKProductsRequest else { return }
        
        delegate.handle(productsRequestError: error)
    }
    
}