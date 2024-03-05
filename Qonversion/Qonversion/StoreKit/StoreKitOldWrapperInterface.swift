//
//  StoreKitOldWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import StoreKit

typealias StoreKitOldProductsCompletion = (SKProductsResponse?, Error?) -> ()
typealias StoreKitOldTransactionsCompletion = ([SKPaymentTransaction], Error?) -> ()

protocol StoreKitOldWrapperInterface {
    
    func products(for ids:[String], completion: @escaping StoreKitOldProductsCompletion)
    
    func restore(with completion: @escaping StoreKitOldTransactionsCompletion)
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet()
    
    func purchase(product: SKProduct, completion: @escaping StoreKitOldTransactionsCompletion)
    
    func finish(transaction: SKPaymentTransaction)
    
}
