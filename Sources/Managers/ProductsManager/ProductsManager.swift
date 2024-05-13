//
//  ProductsManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation
import StoreKit

fileprivate enum Constants: String {
    case productsKey = "qonversion.keys.products"
}

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
        
        var offerings: Qonversion.Offerings = try await productsService.offerings()
        
        do {
            var enrichedOfferings: [Qonversion.Offering] = []
            for var offering in offerings.availableOfferings {
                #warning("This logic should be updated for a new product requirements")
                let resultProducts: [Qonversion.Product] = try await enrich(products: offering.products)
                offering.enrich(products: resultProducts)
                
                enrichedOfferings.append(offering)
            }
            
            offerings.enrich(offerings: enrichedOfferings)
            
            loadedOfferings = offerings
            
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
        
        do {
            let products: [Qonversion.Product] = try await productsService.products()
            
            let resultProducts: [Qonversion.Product] = try await enrich(products: products)
            
            try localStorage.set(resultProducts, forKey: Constants.productsKey.rawValue)
            
            loadedProducts = resultProducts
            
            return resultProducts
        } catch {
            switch error {
            case let productsLoadingError as QonversionError:
                if productsLoadingError.type != .productsLoadingFailed {
                    fallthrough
                }
                
                let errorMessage = "Products loading failed with error: " + productsLoadingError.message
                do {
                    guard let products = try localStorage.object(forKey: Constants.productsKey.rawValue, dataType: [Qonversion.Product].self) else {
                        logger.error(productsLoadingError.message)
                        throw productsLoadingError
                    }
                    
                    let resultProducts: [Qonversion.Product] = try await enrich(products: products)
                    
                    logger.warning(errorMessage + ". Returning cached products.")
                    return resultProducts
                } catch {
                    logger.error(errorMessage + ". Loading cached products also failed with error: " + error.message)
                    throw productsLoadingError
                }
            default:
                throw error
            }
        }
    }
    
    // MARK: - Private
    
    private func enrich(products: [Qonversion.Product]) async throws -> [Qonversion.Product] {
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
        
        return resultProducts
    }
    
}

// MARK: - StoreKitFacadeDelegate

extension ProductsManager: StoreKitFacadeDelegate {
    
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) {
        #warning("Add promo purchase logic")
    }
    
    
}
