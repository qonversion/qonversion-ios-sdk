//
//  Qonversion.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

/// An entry point to use Qonversion SDK.
public final class Qonversion {
    
    // MARK: - Private
    private var userPropertiesManager: UserPropertiesManagerInterface?
    private var deviceManager: DeviceManagerInterface?
    private var remoteConfigManager: RemoteConfigManagerInterface?
    
    private init() { }
    
    // MARK: - Public
    
    /// Use this variable to get the current initialized instance of the Qonversion SDK.
    /// Please, use the variable only after initializing the SDK.
    /// - Returns: the current initialized instance of the ``Qonversion`` SDK
    public static let shared = Qonversion()
    
    /// An entry point to use Qonversion SDK. Call to initialize Qonversion SDK with required and extra configs.
    /// The function is the best way to set additional configs you need to use Qonversion SDK.
    /// - Parameter configuration: a config that contains key SDK settings.
    /// - Returns: Initialized instance of the ``Qonversion`` SDK.
    public static func initialize(with configuration: Configuration) -> Qonversion {
        let assembly: QonversionAssembly = QonversionAssembly(apiKey: configuration.apiKey, userDefaults: configuration.userDefaults)
        Qonversion.shared.userPropertiesManager = assembly.userPropertiesManager()
        Qonversion.shared.deviceManager = assembly.deviceManager()
        Qonversion.shared.remoteConfigManager = assembly.remoteConfigManager()

        return Qonversion.shared
    }
    
    /// Collects Apple Search Ads Attribution data
    /// Available only for iOS 14.3+
    /// See details in the [Apple official documentation](https://developer.apple.com/documentation/iad/setting-up-apple-search-ads-attribution)
    public func collectAppleSearchAdsAttribution() {
        userPropertiesManager?.collectAppleSearchAdsAttribution()
    }
    
    /// Collects advertising ID
    /// On iOS 14.5+, after requesting the app tracking permission using ATT, you need to notify Qonversion if tracking is allowed and IDFA is available.
    public func collectAdvertisingId() {
        deviceManager?.collectAdvertisingId()
    }
    
    /// Sets Qonversion defined user properties, like email or appsFlyer user ID.
    /// - Note that using ``Qonversion/Qonversion/UserPropertyKey/custom`` here will do nothing.
    /// - To set custom user property, use ``Qonversion/Qonversion/setCustomUserProperty(_:key:)``  instead.
    /// - Parameters:
    ///   - userProperty: Property value
    ///   - key: Defined enum key
    public func setUserProperty(_ userProperty: String, key: UserPropertyKey) {
        guard let userPropertiesManager else { return }
        
        userPropertiesManager.setUserProperty(key: key, value: userProperty)
    }
    
    /// Sets custom user property
    /// - Parameters:
    ///   - userProperty: Property value
    ///   - key: Custom property key
    public func setCustomUserProperty(_ userProperty: String, key: String) {
        guard let userPropertiesManager else { return }
        
        userPropertiesManager.setCustomUserProperty(key: key, value: userProperty)
    }
    
    /// This method returns all the properties, set for the current Qonversion user.
    /// All set properties are sent to the server with delay, so if you call
    /// this function right after setting some property, it may not be included in the result.
    ///  - Returns: ``Qonversion/Qonversion/UserProperties`` that contains all the properties, set for the current Qonversion user.
    public func userProperties() async throws -> UserProperties {
        guard let userPropertiesManager else { throw QonversionError.initializationError() }
        
        return try await userPropertiesManager.userProperties()
    }
    
    /// Returns Qonversion default remote config object or one defined by the context key.
    /// Use this function to get the remote config with specific payload and experiment info.
    /// - Parameters:
    ///   - contextKey: Context key to get remote config for
    /// - Returns: ``Qonversion/Qonversion/RemoteConfig`` for the specified context key or default one if no key provided.
    public func remoteConfig(contextKey: String? = nil) async throws -> Qonversion.RemoteConfig {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return try await remoteConfigManager.loadRemoteConfig(contextKey: contextKey)
    }
    
    /// Returns Qonversion remote config objects for all existing context key (including empty one).
    /// Use this function to get the remote configs with specific payload and experiment info.
    /// - Returns: ``Qonversion/Qonversion/RemoteConfigList`` with all the remote configs for the current user.
    public func remoteConfigList() async throws -> Qonversion.RemoteConfigList {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return try await remoteConfigManager.loadRemoteConfigList()
    }

    /// Returns Qonversion remote config objects by a list of context keys.
    /// Use this function to get the remote configs with specific payload and experiment info.
    /// - Parameters:
    ///   - contextKeys:list of context keys to get remote configs for.
    ///   - includeEmptyContextKey:- set to true if you want to include remote config with empty context key to the result
    /// - Returns: ``Qonversion/Qonversion/RemoteConfigList`` with the requested remote configs for the current user.
    public func remoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return try await remoteConfigManager.loadRemoteConfigList(contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to attach the user to the remote configuration.
    /// - Parameters:
    ///   - remoteConfigurationId: identifier of the remote configuration
    /// - Returns: true if attached successfully, false otherwise.
    public func attachUserToRemoteConfiguration(remoteConfigurationId: String) async throws -> Bool {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return await remoteConfigManager.attachUserToRemoteConfig(remoteConfigId: remoteConfigurationId)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to detach the user from the remote configuration.
    /// - Parameters:
    ///   - remoteConfigurationId: identifier of the remote configuration
    /// - Returns: true if detached successfully, false otherwise.
    public func detachUserFromRemoteConfiguration(remoteConfigurationId: String) async throws -> Bool {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return await remoteConfigManager.detachUserFromRemoteConfig(remoteConfigId: remoteConfigurationId)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to attach the user to the experiment.
    /// - Parameters:
    ///   - experimentId: identifier of the experiment
    ///   - groupId: identifier of the experiment group
    /// - Returns: true if attached successfully, false otherwise.
    public func attachUserToExperiment(experimentId: String, groupId: String) async throws -> Bool {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return await remoteConfigManager.attachUserToExperiment(experimentId: experimentId, groupId: groupId)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to detach the user to the experiment.
    /// - Parameters:
    ///   - experimentId: identifier of the experiment 
    /// - Returns: true if detached successfully, false otherwise.
    public func detachUserFromExperiment(experimentId: String) async throws -> Bool {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return await remoteConfigManager.detachUserFromExperiment(experimentId: experimentId)
    }
}
