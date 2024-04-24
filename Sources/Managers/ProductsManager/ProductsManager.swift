//
//  ProductsManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation
import StoreKit

final class ProductsManager: ProductsManagerInterface {
    
    let productsService: ProductsServiceInterface
    let storeKitFacade: StoreKitFacadeInterface
    let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper
    
    var loadedProducts: [Qonversion.Product] = []
    var loadedOfferings: Qonversion.Offerings?
    
    init(productsService: ProductsServiceInterface, storeKitFacade: StoreKitFacadeInterface, localStorage: LocalStorageInterface, logger: LoggerWrapper) {
        self.productsService = productsService
        self.storeKitFacade = storeKitFacade
        self.localStorage = localStorage
        self.logger = logger
    }
    
    func offerings() async throws -> Qonversion.Offerings {
        if let loadedOfferings {
            return loadedOfferings
        }
        
        let offerings: Qonversion.Offerings = try await productsService.offerings()
        
        do {
            let productIds: [String] = offerings.availableOfferings.flatMap { $0.products.map { $0.storeId } }
            
            try await storeKitFacade.products(for: productIds)
            
            // enrich products here
            
            return offerings
        } catch {
            logger.error(error.localizedDescription)
        }
        
        loadedOfferings = offerings
        
        return offerings
    }
    
    func products() async throws -> [Qonversion.Product] {
        guard loadedProducts.isEmpty else {
            return loadedProducts
        }
        
        let products: [Qonversion.Product] = try await productsService.products()
        
        do {
            let productIds: [String] = products.map { $0.storeId }
            let storeProducts: [StoreProductWrapper] = try await storeKitFacade.products(for: productIds)
            
            var resultProducts: [Qonversion.Product] = []
            
            for var product in products {
                guard let storeProductWrapper = storeProducts.first(where: { $0.id == product.storeId }) else { continue }
                
                if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeProduct = storeProductWrapper.product {
                    product.enrich(storeProduct: storeProduct)
                } else if let storeProduct = storeProductWrapper.oldProduct {
                    product.enrich(skProduct: storeProduct)
                }
                
                resultProducts.append(product)
            }
            
            let enrichedProducts: [Qonversion.Product] = try await storeKitFacade.enrich(products: products)
            
            loadedProducts = enrichedProducts
            
            return enrichedProducts
        } catch {
            logger.error(error.localizedDescription)
        }
        
        loadedProducts = products
        
        return products
    }
    
}

// MARK: - StoreKitFacadeDelegate

extension ProductsManager: StoreKitFacadeDelegate {
    
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) {
        
    }
    
    
}
