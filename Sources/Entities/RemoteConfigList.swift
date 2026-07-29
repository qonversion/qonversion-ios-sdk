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

        /// Searches for the remote configuration with a specific context key.
        /// - Parameters:
        ///   - contextKey: context key to search the remote configuration for.
        ///   An empty string is treated as "no context key" and is equivalent
        ///   to calling ``remoteConfigForEmptyContextKey()``.
        /// - Returns: the remote configuration with the specified context key,
        /// or nil if no matching configuration was found.
        public func remoteConfig(for contextKey: String) -> RemoteConfig? {
            return findRemoteConfig(for: contextKey)
        }

        /// Searches for the remote configuration that is not bound to any
        /// context key. A configuration the backend reports no source for is
        /// not a match: it is assigned to nothing at all.
        /// - Returns: the remote configuration without a context key, or nil if
        /// no matching configuration was found.
        public func remoteConfigForEmptyContextKey() -> RemoteConfig? {
            return findRemoteConfig(for: nil)
        }
    }
}

// MARK: - Private

extension Qonversion.RemoteConfigList {
    
    private func findRemoteConfig(for contextKey: String?) -> Qonversion.RemoteConfig? {
        // The decoder normalizes an empty context key to nil, so the lookup key
        // is normalized the same way — otherwise remoteConfig(for: "") could
        // never match anything.
        let normalizedKey: String? = contextKey?.isEmpty == false ? contextKey : nil

        return remoteConfigs.first { config in
            // A config the backend reports no source for is assigned to no
            // context key, not to the empty one.
            guard let source: Qonversion.RemoteConfig.Source = config.source else { return false }

            return source.contextKey == normalizedKey
        }
    }
}
