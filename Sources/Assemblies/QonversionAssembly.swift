//
//  QonversionAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

final class QonversionAssembly {
    
    private let servicesAssembly: ServicesAssembly
    private let miscAssembly: MiscAssembly
    
    required init(apiKey: String, userDefaults: UserDefaults?) {
        let userDefaults = userDefaults ?? UserDefaults.standard
        self.miscAssembly = MiscAssembly(apiKey: apiKey, userDefaults: userDefaults, internalConfig: InternalConfig(userId: ""))
        self.servicesAssembly = ServicesAssembly(apiKey: apiKey, miscAssembly: miscAssembly)
        self.miscAssembly.servicesAssembly = self.servicesAssembly
    }
    
    func userPropertiesManager() -> UserPropertiesManagerInterface {
        let requestProcessor: RequestProcessorInterface = servicesAssembly.requestProcessor()
        let delayCalculator: IncrementalDelayCalculator = miscAssembly.delayCalculator()
        let propertiesStorage: PropertiesStorage = miscAssembly.userPropertiesStorage()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let userPropertiesManager = UserPropertiesManager(requestProcessor: requestProcessor, propertiesStorage: propertiesStorage, delayCalculator: delayCalculator, userIdProvider: miscAssembly.internalConfig, logger: logger)
        
        return userPropertiesManager
    }
    
    func deviceManager() -> DeviceManagerInterface {
        let deviceInfoCollector = servicesAssembly.deviceInfoCollector()
        let deviceService = servicesAssembly.deviceService()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let deviceManager = DeviceManager(deviceInfoCollector: deviceInfoCollector, deviceService: deviceService, logger: logger)
        
        return deviceManager
    }
    
    func productsManager() -> ProductsManagerInterface {
        let productsService: ProductsServiceInterface = servicesAssembly.productsService()
        let storeKitFacade: StoreKitFacade = servicesAssembly.storeKitFacade()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let productsManager = ProductsManager(productsService: productsService, storeKitFacade: storeKitFacade, localStorage: localStorage, logger: logger)
        
        storeKitFacade.delegate = productsManager
        
        return productsManager
    }
    
    func purchasesManager() -> PurchasesManagerInterface {
        let entitlementsService: EntitlementsServiceInterface = servicesAssembly.entitlementsService()
        let localStorage: LocalStorageInterface = miscAssembly.localStorage()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let purchasesManager = PurchasesManager(entitlementsService: entitlementsService, localStorage: localStorage, logger: logger)
        
        return purchasesManager
    }
    
    func remoteConfigManager() -> RemoteConfigManagerInterface {
        let remoteConfigService = servicesAssembly.remoteConfigService()
        let logger: LoggerWrapper = miscAssembly.loggerWrapper()
        let remoteConfigManager = RemoteConfigManager(remoteConfigService: remoteConfigService, logger: logger)

        return remoteConfigManager
    }
}
