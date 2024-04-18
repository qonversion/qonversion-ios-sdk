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
    
    func products() async throws -> [Qonversion.Product] {
        return []
    }
    
}
