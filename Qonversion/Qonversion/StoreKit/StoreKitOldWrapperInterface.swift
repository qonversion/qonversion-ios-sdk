//
//  StoreKitOldWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import StoreKit

typealias StoreKitOldProductsCompletion = (SKProductsResponse?, Error?) -> ()
typealias StoreKitOldPurchaseCompletion = ([SKPaymentTransaction], Error) -> ()

protocol StoreKitOldWrapperInterface {
    
    func loadProducts(for ids:[String], completion: @escaping StoreKitOldProductsCompletion)
    
    func restore()
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet()
    
    func purchase(product: SKProduct, completion: @escaping StoreKitOldPurchaseCompletion)
    
    func finish(transaction: SKPaymentTransaction)
    
}
