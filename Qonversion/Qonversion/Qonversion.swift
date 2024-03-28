//
//  Qonversion.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

public final class Qonversion {
    public static let shared = Qonversion()
    
    private var userPropertiesManager: UserPropertiesManagerInterface?
    
    private init() { }
    
    public static func initialize(with configuration: Configuration) {
        let assembly: QonversionAssembly = QonversionAssembly(apiKey: configuration.apiKey, userDefaults: configuration.userDefaults)
        Qonversion.shared.userPropertiesManager = assembly.userPropertiesManager()
    }
    
    func collectAppleSearchAdsAttribution() {
        // collectAppleSearchAdsAttribution
    }
    
    func setUserProperty(_ userProperty: String, key: UserPropertyKey) {
        guard let userPropertiesManager else { return }
        
        userPropertiesManager.setUserProperty(key: key, value: userProperty)
    }
    
    func setCustomUserProperty(_ userProperty: String, key: String) {
        guard let userPropertiesManager else { return }
        
        userPropertiesManager.setCustomUserProperty(key: key, value: userProperty)
    }
    
    func userProperties() async throws -> UserProperties {
        guard let userPropertiesManager else { throw QonversionError.initializationError() }
        
        return try await userPropertiesManager.userProperties()
    }
    
}
