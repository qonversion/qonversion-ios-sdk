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
        let propertiesStorage = PropertiesStorage(
        let userPropertiesManager = UserPropertiesManager(requestProcessor: requestProcessor, propertiesStorage: <#T##any PropertiesStorage#>, delayCalculator: <#T##IncrementalDelayCalculator#>, internalConfig: <#T##InternalConfig#>)
    }
    
}
