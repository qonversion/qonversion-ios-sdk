//
//  ProductsService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2024.
//

import Foundation

final class ProductsService: ProductsServiceInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let internalConfig: InternalConfig
    
    init(requestProcessor: RequestProcessorInterface, internalConfig: InternalConfig) {
        self.requestProcessor = requestProcessor
        self.internalConfig = internalConfig
    }
    
    func offerings() async throws -> Qonversion.Offerings {
        let request = Request.getOfferings(userId: internalConfig.userId)
        do {
            let offeringsList: [Qonversion.Offering] = try await requestProcessor.process(request: request, responseType: [Qonversion.Offering].self)
            let offerings: Qonversion.Offerings = Qonversion.Offerings(offerings: offeringsList)
            
            return offerings
        } catch {
            throw QonversionError(type: .productsLoadingFailed, message: nil, error: error)
        }
    }
    
    func products() async throws -> [Qonversion.Product] {
        let request = Request.getProducts(userId: internalConfig.userId)
        do {
            let products: [Qonversion.Product] = try await requestProcessor.process(request: request, responseType: [Qonversion.Product].self)
            
            return products
        } catch {
            throw QonversionError(type: .productsLoadingFailed, message: nil, error: error)
        }
    }
    
}
