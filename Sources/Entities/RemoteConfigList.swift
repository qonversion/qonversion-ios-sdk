//
//  RemoteConfigList.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    /// List of remote configurations. It's a wrapper containing several useful functions in addition to requested remote configurations..
    public struct RemoteConfigList: Decodable {
        
        /// Reuqested remote configurations
        public let remoteConfigs: [RemoteConfig]

        init(remoteConfigs: [RemoteConfig]) {
            self.remoteConfigs = remoteConfigs
        }

        /// Searches for remote configuration with the specific context key.
        /// - Parameters:
        ///   - contextKey: context key to search remote configuration for.
        /// - Returns: remote configuration with the specified context key or nil if no matching configuration found.
        public func remoteConfig(for contextKey: String) -> RemoteConfig? {
            return findRemoteConfig(for: contextKey)
        }

        /// Searches for remote configuration with empty context key.
        /// - Returns: remote configuration with empty context key or nil if no matching configuration found.
        public func remoteConfigForEmptyContextKey() -> RemoteConfig? {
            return findRemoteConfig(for: nil)
        }
    }
}

// MARK: - Private

extension Qonversion.RemoteConfigList {
    
    private func findRemoteConfig(for contextKey: String?) -> Qonversion.RemoteConfig? {
        return remoteConfigs.first { config in
            return (contextKey == nil && config.source.contextKey == nil) || config.source.contextKey == contextKey
        }
    }
}
