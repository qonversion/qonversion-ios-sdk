//
//  EntitlementsService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.04.2024.
//

import Foundation

final class EntitlementsService: EntitlementsServiceInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let internalConfig: InternalConfig
    private let logger: LoggerWrapper
    
    init(requestProcessor: RequestProcessorInterface, internalConfig: InternalConfig, logger: LoggerWrapper) {
        self.requestProcessor = requestProcessor
        self.internalConfig = internalConfig
        self.logger = logger
    }
    
    func entitlements() async throws -> [Qonversion.Entitlement] {
        let request = Request.getEntitlements(userId: internalConfig.userId)
        do {
            let entitlements: [Qonversion.Entitlement] = try await requestProcessor.process(request: request, responseType: [Qonversion.Entitlement].self)
            
            return entitlements
        } catch {
            let error = QonversionError(type: .productsLoadingFailed, message: nil, error: error)
            logger.error(error.message)
            throw error
        }
    }
}
