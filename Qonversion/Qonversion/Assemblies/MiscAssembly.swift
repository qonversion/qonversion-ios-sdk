//
//  MiscAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.03.2024.
//

import Foundation

fileprivate enum SDKLevelConstants: String {
    case version = "1.0"
}

fileprivate enum IntConstants: UInt {
    case maxRequestsPerSecond = 5
}

fileprivate enum StringConstants: String {
    case storagePrefix = "io.qonversion.sdk.storage."
    case requestsStorageKey = "requests"
}

final class MiscAssembly {
    
    let apiKey: String
    let userDefaults: UserDefaults
    
    var servicesAssembly: ServicesAssembly!
    var internalConfig: InternalConfig
    
    init(apiKey: String, userDefaults: UserDefaults, internalConfig: InternalConfig) {
        self.apiKey = apiKey
        self.userDefaults = userDefaults
        self.internalConfig = internalConfig
    }
    
    func userIdProvider() -> UserIdProvider {
        return internalConfig
    }
    
    func delayCalculator() -> IncrementalDelayCalculator {
        return IncrementalDelayCalculator()
    }
    
    func userPropertiesStorage() -> UserPropertiesStorage {
        return UserPropertiesStorage()
    }
    
    func requestsStorage() -> RequestsStorageInterface {
        let requestsStorage = RequestsStorage(userDefaults: userDefaults, storeKey: StringConstants.storagePrefix.rawValue + StringConstants.requestsStorageKey.rawValue)
        
        return requestsStorage
    }
    
    func rateLimiter() -> RateLimiterInterface {
        let rateLimiter = RateLimiter(maxRequestsPerSecond: IntConstants.maxRequestsPerSecond.rawValue)
        
        return rateLimiter
    }
    
    func jsonDecoder() -> JSONDecoder {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970
        
        return jsonDecoder
    }
    
    func responseDecoder() -> ResponseDecoderInterface {
        let jsonDecoder = jsonDecoder()
        
        let responseDecoder = ResponseDecoder(decoder: jsonDecoder)
        
        return responseDecoder
    }
    
    func errorHandler() -> NetworkErrorHandlerInterface {
        let criticalErrorCodes: [ResponseCode] = [
            ResponseCode.unauthorized,
            ResponseCode.paymentRequired,
            ResponseCode.forbidden
        ]
        
        let networkErrorHandler = NetworkErrorHandler(criticalErrorCodes: criticalErrorCodes)
        
        return networkErrorHandler
    }
    
    func headersBuilder() -> HeadersBuilderInterface {
        let deviceInfoCollector = servicesAssembly.deviceInfoCollector()
        let headersBuilder = HeadersBuilder(apiKey: apiKey, sdkVersion: SDKLevelConstants.version.rawValue, deviceInfoCollector: deviceInfoCollector)
        
        return headersBuilder
    }
    
}
