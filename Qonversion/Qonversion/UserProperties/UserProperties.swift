//
//  UserProperties.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

public struct UserProperties {
    
    let properties: [UserProperty]
    let definedProperties: [UserProperty]
    let customProperties: [UserProperty]
    let flatPropertiesMap: [String: String]
    let flatDefinedPropertiesMap: [UserPropertyKey: String]
    let flatCustomPropertiesMap: [String: String]

    init(_ properties: [UserProperty]) {
        self.properties = properties

        var definedPropertiesList = [UserProperty]()
        var customPropertiesList = [UserProperty]()
        var propertiesMap = [String: String]()
        var definedPropertiesMap = [UserPropertyKey: String]()
        var customPropertiesMap = [String: String]()
        
        properties.forEach { userProperty in
            propertiesMap[userProperty.key] = userProperty.value
            
            if userProperty.definedKey == .custom {
                customPropertiesList.append(userProperty)
                customPropertiesMap[userProperty.key] = userProperty.value
            } else {
                definedPropertiesList.append(userProperty)
                definedPropertiesMap[userProperty.definedKey] = userProperty.value
            }
        }
        
        definedProperties = definedPropertiesList
        customProperties = customPropertiesList
        flatPropertiesMap = propertiesMap
        flatDefinedPropertiesMap = definedPropertiesMap
        flatCustomPropertiesMap = customPropertiesMap
    }
    
    func property(for key: String) -> UserProperty? {
        return properties.first { $0.key == key }
    }
    
    func definedProperty(for key: UserPropertyKey) -> UserProperty? {
        return definedProperties.first { $0.definedKey == key }
    }
}
