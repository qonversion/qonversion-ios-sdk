//
//  TemporaryFactory.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 29.02.2024.
//

import Foundation
import StoreKit

#warning("remove this file")
final public class TemporaryFactory: StoreKitWrapperDelegate, StoreKitOldWrapperDelegate {
    func handle(productsResponse: SKProductsResponse) {
        
    }
    
    func handle(restoreTransactionsError: Error) {
        
    }
    
    func handleRestoreFinished() {
        
    }
    
    func shouldAdd(storePayment: SKPayment, for product: SKProduct) -> Bool {
        return false
    }
    
    func handle(productsRequestError: Error) {
        
    }
    
    func updated(transactions: [SKPaymentTransaction]) {
        
    }
    
    @available(iOS 15.0, *)
    public func promoPurchaseIntent(product: Product) {
        
    }
    
    
    var facade: StoreKitFacadeInterface?
    
    public init() {
        if #available(iOS 15.0, *) {
            self.facade = StoreKitFacade(storeKitOldWrapper: StoreKitOldWrapper(delegate: self, paymentQueue: SKPaymentQueue.default()), storeKitWrapper: nil, storeKitMapper: StoreKitMapper())
        } else {
            // Fallback on earlier versions
        }
    }
    
    public func test() {
        Task.init {
            do {
                let res = try await facade?.restore()
                print(res)
            } catch {
                print(error)
            }
        }
    }
    
}
