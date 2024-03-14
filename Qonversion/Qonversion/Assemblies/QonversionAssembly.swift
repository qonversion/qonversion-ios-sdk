//
//  QonversionAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

final class QonversionAssembly {
    
    private let servicesAssembly: ServicesAssembly
    
    required init(apiKey: String, userDefaults: UserDefaults?) {
        self.servicesAssembly = ServicesAssembly(apiKey: apiKey, userDefaults: userDefaults)
    }
    
    func userPropertiesManager() -> UserPropertiesManagerInterface {
        let requestProcessor = servicesAssembly.requestProcessor()
        let propertiesStorage = UserPropertiesStorage()
        let userPropertiesManager = UserPropertiesManager(requestProcessor: requestProcessor, propertiesStorage: propertiesStorage, delayCalculator: delayCalculator(), internalConfig: InternalConfig(userId: "da"))
        
        return userPropertiesManager
    }
    
    func delayCalculator() -> IncrementalDelayCalculator {
        return IncrementalDelayCalculator()
    }
    
}
