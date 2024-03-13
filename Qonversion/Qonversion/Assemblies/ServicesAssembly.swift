//
//  ServicesAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

fileprivate enum SDKLevelConstants: String {
    case version = "1.0"
}

fileprivate enum IntConstants: UInt {
    case maxRequestsPerSecond = 5
}

fileprivate enum StringConstants: String {
    case baseURL = "https://api.qonversion.io/"
    case storagePrefix = "io.qonversion.sdk.storage."
    case requestsStorageKey = "requests"
}

final class ServicesAssembly {
    
    private let apiKey: String
    private let userDefaults: UserDefaults
    
    init(apiKey: String, userDefaults: UserDefaults?) {
        self.apiKey = apiKey
        self.userDefaults = userDefaults ?? UserDefaults.standard
    }
    
    func userService() -> UserServiceInterface {
        let requestProcessor = requestProcessor()
        let userService = UserService(requestProcessor: requestProcessor, userDefaults: userDefaults, internalConfig: InternalConfig(userId: ""))
        
        return userService
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
        let deviceInfoCollector = deviceInfoCollector()
        let headersBuilder = HeadersBuilder(apiKey: apiKey, sdkVersion: <#T##String#>, deviceInfoCollector: deviceInfoCollector)
        
        return headersBuilder
    }
    
    func requestProcessor() -> RequestProcessorInterface {
        let networkProvider: NetworkProviderInterface = networkProvider()
        let headersBuilder: HeadersBuilderInterface = headersBuilder()
        let errorHandler: NetworkErrorHandlerInterface = errorHandler()
        let decoder: ResponseDecoderInterface = responseDecoder()
        let requestsStorage: RequestsStorageInterface = requestsStorage()
        let rateLimiter: RateLimiterInterface = rateLimiter()
        
        #warning("Update retriable requests list")
        let retriableRequestsList: [Request] = []
        
        let processor = RequestProcessor(baseURL: StringConstants.baseURL.rawValue, networkProvider: networkProvider, headersBuilder: headersBuilder, errorHandler: errorHandler, decoder: decoder, retriableRequestsList: retriableRequestsList, requestsStorage: requestsStorage, rateLimiter: rateLimiter)
        
        return processor
    }
    
    func deviceInfoCollector() -> DeviceInfoCollectorInterface {
        return DeviceInfoCollector()
    }
    
    func networkProvider() -> NetworkProviderInterface {
        let session: URLSession = urlSession()
        let networkProvider = NetworkProvider(session: session)
        
        return networkProvider
    }
    
    func urlSession() -> URLSession {
        return URLSession.shared
    }
    
}
