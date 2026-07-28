//
//  RemoteConfigList.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    /// List of remote configurations. It's a wrapper containing several useful functions in addition to requested remote configurations..
    // @unchecked: RemoteConfig is @unchecked Sendable itself.
    public struct RemoteConfigList: Decodable, @unchecked Sendable {
        
        /// Reuqested remote configurations
        public let remoteConfigs: [RemoteConfig]

        init(remoteConfigs: [RemoteConfig]) {
            self.remoteConfigs = remoteConfigs
        }

        /// Lossy on purpose: one malformed configuration must degrade the
        /// list, not null it. Two shapes are accepted — the bare array the
        /// `v4/remote-configs` endpoints answer with, and the keyed wrapper
        /// some payloads carry. An all-malformed list still throws (see
        /// ``LossyArray``): that is a schema break, not an empty list.
        public init(from decoder: Decoder) throws {
            if var arrayContainer = try? decoder.unkeyedContainer() {
                remoteConfigs = try LossyArray.decode(RemoteConfig.self, from: &arrayContainer)
                return
            }

            var container = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .remoteConfigs)
            remoteConfigs = try LossyArray.decode(RemoteConfig.self, from: &container)
        }

        private enum CodingKeys: String, CodingKey {
            case remoteConfigs
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
            return (contextKey == nil && config.source?.contextKey == nil) || config.source?.contextKey == contextKey
        }
    }
}
