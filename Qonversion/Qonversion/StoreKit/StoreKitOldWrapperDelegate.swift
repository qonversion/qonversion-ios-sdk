//
//  StoreKitOldWrapperDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import StoreKit

protocol StoreKitOldWrapperDelegate {
    
    func handle(productsResponse: SKProductsResponse)
    func handle(restoreTransactionsError: Error)
    func handleRestoreFinished()
    func shouldAdd(storePayment: SKPayment, for product: SKProduct) -> Bool
    func productsRequestDidFail(with error: Error)
    func updatedTransactions(_ transactions: [SKPaymentTransaction])
    
}
