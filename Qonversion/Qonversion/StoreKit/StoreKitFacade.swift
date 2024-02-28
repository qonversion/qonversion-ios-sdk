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
    let storeKitMapper: StoreKitMapperInterface
    
    init(storeKitOldWrapper: StoreKitOldWrapperInterface?, storeKitWrapper: StoreKitWrapperInterface?, storeKitMapper: StoreKitMapperInterface) {
        self.storeKitOldWrapper = storeKitOldWrapper
        self.storeKitWrapper = storeKitWrapper
        self.storeKitMapper = storeKitMapper
    }
    
    func currentEntitlements() async -> [String] {
        guard #available(iOS 15.0, *), let storeKitWrapper = storeKitWrapper else { return [] }
        
        let transactions: [Transaction] = await storeKitWrapper.currentEntitlements()
        return []
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
