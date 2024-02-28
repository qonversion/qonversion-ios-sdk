//
//  StoreKitFacade.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import Foundation
import StoreKit

class StoreKitFacade: StoreKitFacadeInterface {
    let storeKitOldWrapper: StoreKitOldWrapperInterface?
    
    let storeKitWrapper: StoreKitWrapperInterface?
    
    init(storeKitOldWrapper: StoreKitOldWrapperInterface?, storeKitWrapper: StoreKitWrapperInterface?) {
        self.storeKitOldWrapper = storeKitOldWrapper
        self.storeKitWrapper = storeKitWrapper
    }
    
    func currentEntitlements() async -> [String] {
        guard let storeKitWrapper = storeKitWrapper else { return [] }
        
        if #available(iOS 15.0, *) {
            let transactions: [Transaction] = await storeKitWrapper.currentEntitlements()
            return []
        } else {
            return []
        }
    }
    
    func restore() async throws {
        
    }
    
    func historicalData() async -> [String] {
        return []
    }
    
    func finish(transaction: SKPaymentTransaction) {
        
    }
    
    @available(iOS 15.0, *)
    func finish(transaction: Transaction) {
        
    }
    
    func subscribe() async -> [String] {
        return []
    }
    
    func products(for ids: [String]) async throws -> [String] {
        return []
    }
    
}
