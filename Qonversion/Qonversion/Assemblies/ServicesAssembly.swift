//
//  ServicesAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

fileprivate enum StringConstants: String {
    case baseURL = "https://api.qonversion.io/"
}

final class ServicesAssembly {
    
    private let apiKey: String
    private let userDefaults: UserDefaults
    private let miscAssembly: MiscAssembly
    
    init(apiKey: String, userDefaults: UserDefaults, miscAssembly: MiscAssembly) {
        self.apiKey = apiKey
        self.userDefaults = userDefaults
        self.miscAssembly = miscAssembly
    }
    
    func userService() -> UserServiceInterface {
        let requestProcessor = requestProcessor()
        let userService = UserService(requestProcessor: requestProcessor, userDefaults: userDefaults, internalConfig: InternalConfig(userId: ""))
        
        return userService
    }
    
    func requestProcessor() -> RequestProcessorInterface {
        let networkProvider: NetworkProviderInterface = networkProvider()
        let headersBuilder: HeadersBuilderInterface = miscAssembly.headersBuilder()
        let errorHandler: NetworkErrorHandlerInterface = miscAssembly.errorHandler()
        let decoder: ResponseDecoderInterface = miscAssembly.responseDecoder()
        let requestsStorage: RequestsStorageInterface = miscAssembly.requestsStorage()
        let rateLimiter: RateLimiterInterface = miscAssembly.rateLimiter()
        
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
