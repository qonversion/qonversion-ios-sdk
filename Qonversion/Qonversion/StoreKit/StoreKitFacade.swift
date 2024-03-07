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
        #warning("Map response here")
        
        return []
    }
    
    func restore() async throws -> [Qonversion.Transaction] {
        if #available(iOS 15.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            try await storeKitWrapper.restore()

            #warning("Fetch all products and map response here")
            let res = try await historicalData()
            return [""]
        } else {
            let res = try await historicalData()
            return [""]
        }
    }
    
    func historicalData() async throws -> [String] {
        if #available(iOS 15.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            let products = try await storeKitWrapper.fetchAll()
            #warning("Map response here")
            return [products.description]
        } else {
            guard let storeKitWrapper = storeKitOldWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            return try await withCheckedThrowingContinuation { continuation in
                storeKitWrapper.restore { response, error in
                    if let error {
                        #warning("Handle error here")
                        continuation.resume(throwing: QonversionError(type: .critical))
                    } else {
                        #warning("Map response here")
                        continuation.resume(returning: [""])
                    }
                }
            }
        }
    }
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {
        guard let storeKitWrapper = storeKitOldWrapper else { return }
        
        storeKitWrapper.presentCodeRedemptionSheet()
    }
    
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
        
        try await storeKitWrapper.presentOfferCodeRedeemSheet(in: scene)
    }
    
    func finish(transaction: SKPaymentTransaction) {
        guard let storeKitWrapper = storeKitOldWrapper else { return }
        
        storeKitWrapper.finish(transaction: transaction)
    }
    
    @available(iOS 15.0, *)
    func finish(transaction: Transaction) async {
        guard let storeKitWrapper = storeKitWrapper else { return }
        
        await transaction.finish()
    }
    
    func subscribe() async -> [String] {
        return []
    }
    
    func products(for ids: [String]) async throws -> [String] {
        if #available(iOS 15.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            let products = try await storeKitWrapper.products(for: ids)
            #warning("Map response here")
            return [products.description]
        } else {
            guard let storeKitWrapper = storeKitOldWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            return try await withCheckedThrowingContinuation { continuation in
                storeKitWrapper.products(for: ids, completion: { response, error in
                    if let error {
                        #warning("Handle error here")
                        continuation.resume(throwing: QonversionError(type: .critical))
                    } else {
                        #warning("Map response here")
                        continuation.resume(returning: [""])
                    }
                })
            }
        }
    }
    
}
