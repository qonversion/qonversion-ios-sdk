//
//  StoreKitOldWrapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import StoreKit

protocol StoreKitOldWrapperInterface {
    
    func loadProducts(for ids:[String])
    func restore()
    func presentCodeRedemptionSheet()
    func purchase(product: SKProduct)
    func finish(transaction: SKPaymentTransaction)
    
}
