//
//  UserPropertiesManagerInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

protocol UserPropertiesManagerInterface {
  
    func userProperties() async throws -> UserProperties
    
    func setUserProperty(key: UserPropertyKey, value: String)

    func setCustomUserProperty(key: String, value: String)
    
    func sendProperties() async throws
    
    func clearDelayedProperties()
}
