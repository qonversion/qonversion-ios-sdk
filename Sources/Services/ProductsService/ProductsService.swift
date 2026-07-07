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
    
    func productPermissions() async throws -> [String: [String]] {
        let request = Request.getProductPermissions()
        do {
            let response: ProductsPermissions = try await requestProcessor.process(request: request, responseType: ProductsPermissions.self)

            return response.productsPermissions
        } catch {
            throw QonversionError(type: .productPermissionsLoadingFailed, message: nil, error: error)
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
