//
//  ProductsManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation

final class ProductsManager: ProductsManagerInterface {
    
    let productsService: ProductsServiceInterface
    let storeKitFacade: StoreKitFacadeInterface
    let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper
    
    var loadedProducts: [Qonversion.Product] = []
    
    init(productsService: ProductsServiceInterface, storeKitFacade: StoreKitFacadeInterface, localStorage: LocalStorageInterface, logger: LoggerWrapper) {
        self.productsService = productsService
        self.storeKitFacade = storeKitFacade
        self.localStorage = localStorage
        self.logger = logger
    }
    
    func products() async throws -> [Qonversion.Product] {
        guard loadedProducts.isEmpty else {
            return loadedProducts
        }
        
        let products: [Qonversion.Product] = try await productsService.products()
        
        let productIds: [String] = products.map { $0.storeId }
        
        do {
            try await storeKitFacade.products(for: productIds)
            
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
