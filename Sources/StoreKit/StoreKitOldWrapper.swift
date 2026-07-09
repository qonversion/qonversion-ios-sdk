//
//  StoreKitOldWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import Foundation
import StoreKit

class StoreKitOldWrapper: NSObject, StoreKitOldWrapperInterface {
    
    let paymentQueue: SKPaymentQueue
    
    // Weak: the delegate (facade) holds the wrapper itself.
    weak var delegate: StoreKitOldWrapperDelegate?

    // Mutated from SDK call threads and read/cleared from the SKPaymentQueue
    // delegate thread.
    private let completionsLock = NSLock()
    var productsRequest: SKProductsRequest?
    var productsCompletions: [SKProductsRequest: StoreKitOldProductsCompletion] = [:]
    var purchaseCompletions: [SKPayment: StoreKitOldTransactionsCompletion] = [:]
    var restoreCompletions: [StoreKitOldTransactionsCompletion] = []
    
    init(paymentQueue: SKPaymentQueue) {
        self.paymentQueue = paymentQueue
        
        super.init()
        
        paymentQueue.add(self)
    }
    
    func products(for ids:[String], completion: @escaping  StoreKitOldProductsCompletion) {
        let request = SKProductsRequest.init(productIdentifiers: Set(ids))
        request.delegate = self

        completionsLock.lock()
        productsRequest = request
        productsCompletions[request] = completion
        completionsLock.unlock()

        request.start()
    }
    
    func restore(with completion: @escaping StoreKitOldTransactionsCompletion) {
        completionsLock.lock()
        let isRestoreInProgress: Bool = !restoreCompletions.isEmpty
        restoreCompletions.append(completion)
        completionsLock.unlock()

        guard !isRestoreInProgress else { return }
        paymentQueue.restoreCompletedTransactions()
    }
    
    #if os(iOS) || os(visionOS)
    @available(iOS 14.0, visionOS 1.0, *)
    func presentCodeRedemptionSheet() {
        paymentQueue.presentCodeRedemptionSheet()
    }
    #endif
    
    func purchase(product: SKProduct, completion: @escaping StoreKitOldTransactionsCompletion) {
        let payment = SKPayment(product: product)

        // Registered BEFORE the payment is enqueued: the queue delegate may
        // fire on another thread right away.
        completionsLock.lock()
        purchaseCompletions[payment] = completion
        completionsLock.unlock()

        paymentQueue.add(payment)
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
        completionsLock.lock()
        let hasRestoreCompletions: Bool = !restoreCompletions.isEmpty
        completionsLock.unlock()
        if restoredTransactions.count > 0, hasRestoreCompletions {
            fireRestoreCompletions(with: restoredTransactions)
        }
        
        firePurchaseCompletions(with: transactions)
        
        completionsLock.lock()
        let hasPurchaseCompletions: Bool = !purchaseCompletions.isEmpty
        completionsLock.unlock()
        if !hasPurchaseCompletions {
            delegate?.updated(transactions: transactions)
        }
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        completionsLock.lock()
        let hasRestoreCompletions: Bool = !restoreCompletions.isEmpty
        completionsLock.unlock()
        guard hasRestoreCompletions else {
            delegate?.handle(restoreTransactionsError: error)
            return
        }
        
        fireRestoreCompletions(with: [], error: error)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return delegate?.shouldAdd(storePayment: payment, for: product) ?? true
    }
    
}

// MARK: - SKProductsRequestDelegate

extension StoreKitOldWrapper: SKProductsRequestDelegate {
   
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        completionsLock.lock()
        let completion: StoreKitOldProductsCompletion? = productsCompletions.removeValue(forKey: request)
        completionsLock.unlock()

        guard let completion else {
            delegate?.handle(productsResponse: response)
            return
        }
        
        completion(response, nil)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        guard request is SKProductsRequest else { return }
        
        delegate?.handle(productsRequestError: error)
    }
    
}

// MARK: - Private

extension StoreKitOldWrapper {
    
    func fireRestoreCompletions(with transactions: [SKPaymentTransaction], error: Error? = nil) {
        completionsLock.lock()
        let completions: [StoreKitOldTransactionsCompletion] = restoreCompletions
        restoreCompletions.removeAll()
        completionsLock.unlock()

        completions.forEach { $0(transactions, error) }
    }
    
    func firePurchaseCompletions(with transactions: [SKPaymentTransaction]) {
        completionsLock.lock()
        let completionsCopy: [SKPayment: StoreKitOldTransactionsCompletion] = purchaseCompletions
        completionsLock.unlock()

        completionsCopy.keys.forEach { payment in
            if let _: SKPaymentTransaction = transactions.first(where: { $0.payment == payment }),
               let completion: StoreKitOldTransactionsCompletion = completionsCopy[payment] {
                completion(transactions, nil)
                completionsLock.lock()
                purchaseCompletions[payment] = nil
                completionsLock.unlock()
            }
        }
    }
}
