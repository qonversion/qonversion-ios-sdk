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
        
        /// Initializer of Configuration.
        /// 
        /// Launch with ``Qonversion/LaunchMode/analytics`` mode to use Qonversion with your existing in-app subscription flow to get comprehensive subscription analytics and user engagement tools, and send the data to the leading marketing, analytics, and engagement platforms.
        /// - Important: Using ``Qonversion/LaunchMode/analytics`` you should process purchases by yourself. Qonversion SDK will only track revenue, but not finish transactions.
        /// - Parameters:
        ///   - apiKey: Your project key from Qonversion Dashboard to setup the SDK
        ///   - launchMode:launch mode of the Qonversion SDK.
        public init(apiKey: String, launchMode: LaunchMode) {
            self.apiKey = apiKey
            self.launchMode = launchMode
        }
        
        /// Set user defaults with the suite name to share it between your app and the shared extension.
        /// - Parameters:
        ///  - userDefaults: the user defaults with the suite name
        mutating func setCustomUserDefaults(_ userDefaults: UserDefaults) {
            self.userDefaults = userDefaults
        }
    }
}
