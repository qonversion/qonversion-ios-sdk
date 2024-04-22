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
    private let miscAssembly: MiscAssembly
    
    private var deviceInfoCollectorInstance: DeviceInfoCollector?
    
    init(apiKey: String, miscAssembly: MiscAssembly) {
        self.apiKey = apiKey
        self.miscAssembly = miscAssembly
    }
    
    func userService() -> UserServiceInterface {
        let requestProcessor: RequestProcessorInterface = requestProcessor()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let userService = UserService(requestProcessor: requestProcessor, localStorage: localStorage, internalConfig: miscAssembly.internalConfig)
        
        return userService
    }
    
    func deviceService() -> DeviceServiceInterface {
        let requestProcessor: RequestProcessorInterface = requestProcessor()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let encoder: JSONEncoder = miscAssembly.encoder()
        let deviceService = DeviceService(requestProcessor: requestProcessor, localStorage: localStorage, userIdProvider: miscAssembly.internalConfig, encoder: encoder)
        
        return deviceService
    }
    
    func remoteConfigService() -> RemoteConfigServiceInterface {
        let requestProcessor: RequestProcessorInterface = requestProcessor()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let remoteConfigService = RemoteConfigService(requestProcessor: requestProcessor, userIdProvider: miscAssembly.internalConfig, logger: logger)

        return remoteConfigService
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
        if let deviceInfoCollectorInstance {
            return deviceInfoCollectorInstance
        }
        
        let deviceInfoCollector = DeviceInfoCollector()
        deviceInfoCollectorInstance = deviceInfoCollector
        
        return deviceInfoCollector
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
