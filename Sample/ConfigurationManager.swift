//
//  ConfigurationManager.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

enum ConfigurationManager {
    private static let qonversionPrefsKey = "qonversion_config"
    private static let projectKeyKey = "project_key"
    private static let apiUrlKey = "api_url"
    
    static let defaultProjectKey = "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2"
    
    private static var userDefaults: UserDefaults {
        UserDefaults.standard
    }
    
    static func getProjectKey() -> String {
        let stored = userDefaults.string(forKey: projectKeyKey)
        if let stored = stored, !stored.isEmpty {
            return stored
        }
        return defaultProjectKey
    }
    
    static func getApiUrl() -> String? {
        userDefaults.string(forKey: apiUrlKey)
    }
    
    static func storeConfiguration(projectKey: String, apiUrl: String?) {
        if projectKey.isEmpty {
            userDefaults.removeObject(forKey: projectKeyKey)
        } else {
            userDefaults.set(projectKey, forKey: projectKeyKey)
        }
        
        if let apiUrl = apiUrl, !apiUrl.isEmpty {
            userDefaults.set(apiUrl, forKey: apiUrlKey)
        } else {
            userDefaults.removeObject(forKey: apiUrlKey)
        }
        
        userDefaults.synchronize()
    }
    
    static func resetConfiguration() {
        userDefaults.removeObject(forKey: projectKeyKey)
        userDefaults.removeObject(forKey: apiUrlKey)
        userDefaults.synchronize()
    }
    
    static var hasCustomConfiguration: Bool {
        let projectKey = userDefaults.string(forKey: projectKeyKey)
        let apiUrl = userDefaults.string(forKey: apiUrlKey)
        return (projectKey != nil && !projectKey!.isEmpty) || (apiUrl != nil && !apiUrl!.isEmpty)
    }
}
