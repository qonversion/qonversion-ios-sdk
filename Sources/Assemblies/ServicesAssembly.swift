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
        let requestProcessor = requestProcessor()
        let localStorage = miscAssembly.localStorage()
        let userService = UserService(requestProcessor: requestProcessor, localStorage: localStorage, internalConfig: miscAssembly.internalConfig)
        
        return userService
    }
    
    func productsService() -> ProductsServiceInterface {
        let requestProcessor = requestProcessor()
        let productsService = ProductsService(requestProcessor: requestProcessor, internalConfig: miscAssembly.internalConfig)
        
        return productsService
    }
    
    func storeKitMapper() -> StoreKitMapperInterface {
        let mapper = StoreKitMapper()
        
        return mapper
    }
    
    func storeKitFacade() -> StoreKitFacade {
        let mapper: StoreKitMapperInterface = storeKitMapper()
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *) {
            let wrapper: StoreKitWrapper = storeKitWrapper()
            
            let storeKitFacade = StoreKitFacade(storeKitWrapper: wrapper, storeKitMapper: mapper)
            
            wrapper.delegate = storeKitFacade
            
            return storeKitFacade
        } else {
            let wrapper: StoreKitOldWrapper = storeKitOldWrapper()
            
            let storeKitFacade = StoreKitFacade(storeKitOldWrapper: wrapper, storeKitMapper: mapper)
            wrapper.delegate = storeKitFacade
            
            return storeKitFacade
        }
        
    }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func storeKitWrapper() -> StoreKitWrapper {
        let storeKitWrapper = StoreKitWrapper()
        
        return storeKitWrapper
    }
    
    func storeKitOldWrapper() -> StoreKitOldWrapper {
        let storeKitOldWrapper = StoreKitOldWrapper(paymentQueue: miscAssembly.paymentQueue())
        
        return storeKitOldWrapper
    }
    
    func deviceService() -> DeviceServiceInterface {
        let requestProcessor = requestProcessor()
        let localStorage = miscAssembly.localStorage()
        let encoder = miscAssembly.encoder()
        let deviceService = DeviceService(requestProcessor: requestProcessor, localStorage: localStorage, userIdProvider: miscAssembly.internalConfig, encoder: encoder)
        
        return deviceService
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
