//
//  MiscAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.03.2024.
//

import Foundation
import OSLog
import StoreKit

fileprivate enum SDKLevelConstants: String {
    case version = "1.0"
}

fileprivate enum IntConstants: UInt {
    case maxRequestsPerSecond = 5
}

fileprivate enum StringConstants: String {
    case requestsStorageKey = "requests"
}

final class MiscAssembly {
    
    let apiKey: String
    let userDefaults: UserDefaults
    
    var servicesAssembly: ServicesAssembly!
    var internalConfig: InternalConfig

    // One instance SDK-wide: the user gate notifies through it, and every
    // user-scoped cache registers with it.
    private let userChangesNotifierInstance = UserChangesNotifier()

    init(apiKey: String, userDefaults: UserDefaults, internalConfig: InternalConfig) {
        self.apiKey = apiKey
        self.userDefaults = userDefaults
        self.internalConfig = internalConfig
    }

    func userChangesNotifier() -> UserChangesNotifier {
        return userChangesNotifierInstance
    }
    
    func localStorage() -> LocalStorage {
        let encoder: JSONEncoder = encoder()
        let decoder: JSONDecoder = jsonDecoder()
        let localStorage = LocalStorage(userDefaults: userDefaults, encoder: encoder, decoder: decoder)

        return localStorage
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
    
    func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Must mirror jsonDecoder(): the cache round-trip (e.g. User.creationDate)
        // breaks with mismatched date strategies.
        encoder.dateEncodingStrategy = .iso8601

        return encoder
    }
    
    func requestsStorage() -> RequestsStorageInterface {
        // Scoped by apiKey: the replayed requests are stamped with the CURRENT
        // Authorization, so another project's queue must never leak into it.
        let storeKey = InternalConstants.storagePrefix.rawValue + StringConstants.requestsStorageKey.rawValue + "." + apiKey
        let requestsStorage = RequestsStorage(userDefaults: userDefaults, storeKey: storeKey)

        return requestsStorage
    }
    
    func loggerWrapper() -> LoggerWrapper {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            let logger = Logger(subsystem: "io.qonversion.sdk", category: "Internal")
            
            return LoggerWrapper(logger: logger, logLevel: internalConfig.logLevel)
        } else {
            return LoggerWrapper()
        }
    }
    
    func rateLimiter() -> RateLimiterInterface {
        let rateLimiter = RateLimiter(maxRequestsPerSecond: IntConstants.maxRequestsPerSecond.rawValue)

        return rateLimiter
    }
    
    func jsonDecoder() -> JSONDecoder {
        let jsonDecoder = JSONDecoder()
        // v4 API: all dates are RFC3339.
        jsonDecoder.dateDecodingStrategy = .iso8601
        
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

        let responseDecoder: ResponseDecoderInterface = responseDecoder()

        let networkErrorHandler = NetworkErrorHandler(criticalErrorCodes: criticalErrorCodes, decoder: responseDecoder)
        
        return networkErrorHandler
    }
    
    func headersBuilder() -> HeadersBuilderInterface {
        let deviceInfoCollector = servicesAssembly.deviceInfoCollector()
        let headersBuilder = HeadersBuilder(apiKey: apiKey, sdkVersion: SDKLevelConstants.version.rawValue, deviceInfoCollector: deviceInfoCollector, userDefaults: userDefaults)
        
        return headersBuilder
    }
    
    func paymentQueue() -> SKPaymentQueue {
        return SKPaymentQueue.default()
    }
}
