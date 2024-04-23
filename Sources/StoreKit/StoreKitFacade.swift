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
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    var loadedProducts: [String: StoreKit.Product]? { _loadedProducts as? [String: StoreKit.Product] }
    
    var _loadedProducts: [String: Any] = [:]
    
    var loadedOldProducts: [String: SKProduct] = [:]
    
    init(storeKitOldWrapper: StoreKitOldWrapperInterface, storeKitMapper: StoreKitMapperInterface) {
        self.storeKitOldWrapper = storeKitOldWrapper
        self.storeKitWrapper = nil
        self.storeKitMapper = storeKitMapper
    }
    
    init(storeKitWrapper: StoreKitWrapperInterface, storeKitMapper: StoreKitMapperInterface) {
        self.storeKitOldWrapper = nil
        self.storeKitWrapper = storeKitWrapper
        self.storeKitMapper = storeKitMapper
    }
    
    func enrich(products: [Qonversion.Product]) async throws -> [Qonversion.Product] {
        let productIds: [String] = products.map { $0.storeId }
        
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeKitWrapper {
            let storeProducts = self.loadedProducts ?? [:]
            let unavaliableProductIds: [String] = productIds.filter { !storeProducts.keys.contains($0) }
            
            var enrichedProducts: [Qonversion.Product] = []
            for var product in products {
                if let storeProduct = storeProducts[product.storeId] {
                    product.enrich(storeProduct: storeProduct)
                    enrichedProducts.append(product)
                }
            }
            
            return enrichedProducts
        } else if let storeKitOldWrapper {
            let unavaliableProductIds: [String] = productIds.filter { !loadedOldProducts.keys.contains($0) }
            var enrichedProducts: [Qonversion.Product] = []
            
            if !unavaliableProductIds.isEmpty {
                try await self.products(for: unavaliableProductIds)
            }
            
            for var product in products {
                if let storeProduct = loadedOldProducts[product.storeId] {
                    product.enrich(skProduct: storeProduct)
                    enrichedProducts.append(product)
                }
            }
            
            return enrichedProducts
        }
        
        return products
    }
    
    func currentEntitlements() async -> [Qonversion.Transaction] {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeKitWrapper = storeKitWrapper else { return [] }
        
        let transactions: [StoreKit.Transaction] = await storeKitWrapper.currentEntitlements()
        #warning("Map response here")
        
        return []
    }
    
    func restore() async throws -> [Qonversion.Transaction] {
        if #available(iOS 15.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            try await storeKitWrapper.restore()

            #warning("Fetch all products and map response here")
            let res = try await historicalData()
            return []
        } else {
            let res = try await historicalData()
            return []
        }
    }
    
    func historicalData() async throws -> [Qonversion.Transaction] {
        if #available(iOS 15.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            let products = try await storeKitWrapper.fetchAll()
            #warning("Map response here")
            return []
        } else {
            guard let storeKitWrapper = storeKitOldWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            return try await withCheckedThrowingContinuation { continuation in
                storeKitWrapper.restore { response, error in
                    if let error {
                        #warning("Handle error here")
                        continuation.resume(throwing: QonversionError(type: .critical))
                    } else {
                        #warning("Map response here")
                        continuation.resume(returning: [])
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
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func finish(transaction: StoreKit.Transaction) async {
        guard let storeKitWrapper = storeKitWrapper else { return }
        
        await transaction.finish()
    }
    
    func subscribe() async -> [Qonversion.Transaction] {
        return []
    }
    
    @discardableResult
    func products(for ids: [String]) async throws -> [String] {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            let products = try await storeKitWrapper.products(for: ids)
            products.forEach {
                _loadedProducts[$0.id] = $0
            }
            
            #warning("Map response here")
            return [products.description]
        } else {
            guard let storeKitWrapper = storeKitOldWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            return try await withCheckedThrowingContinuation { continuation in
                storeKitWrapper.products(for: ids, completion: { [weak self] response, error in
                    guard let self else { return }
                    
                    if let error {
                        #warning("Handle error here")
                        continuation.resume(throwing: QonversionError(type: .critical))
                    } else {
                        #warning("Map response here")
                        response?.products.forEach {
                            self.loadedOldProducts[$0.productIdentifier] = $0
                        }
                        continuation.resume(returning: [""])
                    }
                })
            }
        }
    }
    
}
