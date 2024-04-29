//
//  UserProperties.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

extension Qonversion {
    
    /// Struct contains all information about the current user properties
    public struct UserProperties {
        
        /// List of all user properties.
        public let properties: [UserProperty]
        
        /// List of user properties, set for the Qonversion defined keys.
        /// This is a subset of all ``Qonversion/Qonversion/UserProperties/properties`` list.
        public let definedProperties: [UserProperty]
        
        /// List of user properties, set for custom keys.
        /// This is a subset of all ``Qonversion/Qonversion/UserProperties/properties`` list.
        public let customProperties: [UserProperty]
        
        /// Map of all user properties.
        /// This is a flattened version of the ``Qonversion/Qonversion/UserProperties/properties`` list as a key-value map.
        public let flatPropertiesMap: [String: String]
        
        /// Map of user properties, set for the Qonversion defined keys.
        /// This is a flattened version of the ``Qonversion/Qonversion/UserProperties/definedProperties`` list as a key-value map, where keys are values from ``Qonversion/Qonversion/UserPropertyKey``.
        public let flatDefinedPropertiesMap: [UserPropertyKey: String]
        
        /// Map of user properties, set for custom keys.
        /// This is a flattened version of the ``Qonversion/UserProperties/customProperties`` list as a key-value map.
        public let flatCustomPropertiesMap: [String: String]

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
        
        /// Function returns the property for a custom key
        /// - Parameters:
        ///  - key: a key for the property
        /// - Returns: the property for a custom key
        public func property(for key: String) -> UserProperty? {
            return properties.first { $0.key == key }
        }
        
        /// Function returns the property for a defined key
        /// - Parameters:
        ///  - key: a key for the property
        /// - Returns: the property for a defined key
        public func definedProperty(for key: UserPropertyKey) -> UserProperty? {
            return definedProperties.first { $0.definedKey == key }
        }
    }
}
