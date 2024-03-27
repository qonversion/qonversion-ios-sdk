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
        self.servicesAssembly = ServicesAssembly(apiKey: apiKey, userDefaults: userDefaults)
        self.miscAssembly = MiscAssembly()
    }
    
    func userPropertiesManager() -> UserPropertiesManagerInterface {
        let requestProcessor: RequestProcessorInterface = servicesAssembly.requestProcessor()
        let delayCalculator: IncrementalDelayCalculator = miscAssembly.delayCalculator()
        let propertiesStorage: PropertiesStorage = miscAssembly.userPropertiesStorage()
        let userPropertiesManager = UserPropertiesManager(requestProcessor: requestProcessor, propertiesStorage: propertiesStorage, delayCalculator: delayCalculator, internalConfig: InternalConfig(userId: "da"))
        
        return userPropertiesManager
    }
    
}
