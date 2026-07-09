//
//  TemporaryFactory.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 29.02.2024.
//

import Foundation
import StoreKit

// TODO: remove this file once the test stack is assembled without it.
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
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public func promoPurchaseIntent(product: Product) {
        
    }
    
    
    var facade: StoreKitFacadeInterface?
    
    public init() {
        if #available(iOS 15.0, *) {
            self.facade = StoreKitFacade(storeKitOldWrapper: StoreKitOldWrapper(paymentQueue: SKPaymentQueue.default()), storeKitMapper: StoreKitMapper())
        } else {
            // Fallback on earlier versions
        }
    }
    
    public func test() {
        let facade = self.facade
        Task {
            do {
                let res: [Qonversion.Transaction]? = try await facade?.restore()
                print(res ?? [])
            } catch {
                print(error)
            }
        }
    }
}
