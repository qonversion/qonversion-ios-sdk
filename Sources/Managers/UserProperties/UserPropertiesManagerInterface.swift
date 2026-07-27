//
//  UserPropertiesManagerInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

protocol UserPropertiesManagerInterface {
  
    func userProperties() async throws -> Qonversion.UserProperties
    
    func setUserProperty(key: Qonversion.UserPropertyKey, value: String)

    func setCustomUserProperty(key: String, value: String)
    
    /// Sends the pending batch. `force` waits out a batch already in flight
    /// and then sends whatever is still pending, instead of returning early —
    /// the caller needs the properties to have reached the backend.
    func sendProperties(force: Bool) async throws

    func clearDelayedProperties()
    
    func collectAppleSearchAdsAttribution()

    /// Collects attribution ids of integrated third-party SDKs (Adjust,
    /// AppsFlyer, Facebook) as user properties.
    func collectIntegrationsData()
}

extension UserPropertiesManagerInterface {

    /// The batched send: a batch already in flight covers the current
    /// snapshot, so the call returns without starting a second one.
    func sendProperties() async throws {
        try await sendProperties(force: false)
    }
}
