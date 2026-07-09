//
//  Configuration.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.03.2024.
//

import Foundation

extension Qonversion {
    
    /// Struct used to set the SDK main and additional configurations.
    public struct Configuration {
        
        /// Your project key from Qonversion Dashboard to setup the SDK
        let apiKey: String
        
        /// Launch mode of the Qonversion SDK.
        let launchMode: LaunchMode
        
        var userDefaults: UserDefaults? = nil

        /// Base API url: the normalized proxy url when set, nil otherwise.
        let baseURL: String?

        /// How long cached entitlements stay eligible for the local fallback.
        let entitlementsCacheLifetime: EntitlementsCacheLifetime

        /// Minimal severity the SDK writes to the unified log.
        let logLevel: LogLevel

        /// Initializer of Configuration.
        /// 
        /// Launch with ``Qonversion/LaunchMode/analytics`` mode to use Qonversion with your existing in-app subscription flow to get comprehensive subscription analytics and user engagement tools, and send the data to the leading marketing, analytics, and engagement platforms.
        /// - Important: Using ``Qonversion/LaunchMode/analytics`` you should process purchases by yourself. Qonversion SDK will only track revenue, but not finish transactions.
        /// - Parameters:
        ///   - apiKey: Your project key from Qonversion Dashboard to setup the SDK
        ///   - launchMode: launch mode of the Qonversion SDK.
        ///   - proxyURL: URL of your proxy server which redirects all the requests from the app to our API. Please, check the documentation and contact us before using this feature.
        ///   - entitlementsCacheLifetime: how long cached entitlements stay eligible for the local fallback when the backend is unreachable. The default value is `.month`.
        ///   - logLevel: minimal severity the SDK writes to the unified log. The default value is `.verbose`.
        public init(apiKey: String, launchMode: LaunchMode, proxyURL: String? = nil, entitlementsCacheLifetime: EntitlementsCacheLifetime = .month, logLevel: LogLevel = .verbose) {
            self.apiKey = apiKey
            self.launchMode = launchMode
            self.baseURL = proxyURL.map(Configuration.normalizedBaseURL)
            self.entitlementsCacheLifetime = entitlementsCacheLifetime
            self.logLevel = logLevel
        }

        private static func normalizedBaseURL(_ url: String) -> String {
            var result: String = url
            if !result.hasPrefix("http://") && !result.hasPrefix("https://") {
                result = "https://" + result
            }
            if !result.hasSuffix("/") {
                result += "/"
            }
            return result
        }
        
        /// Set user defaults with the suite name to share it between your app and the shared extension.
        /// - Parameters:
        ///  - userDefaults: the user defaults with the suite name
        mutating func setCustomUserDefaults(_ userDefaults: UserDefaults) {
            self.userDefaults = userDefaults
        }
    }
}
