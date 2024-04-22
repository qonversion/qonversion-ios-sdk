//
//  RemoteConfigList.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    public class RemoteConfigList: Decodable {
        let remoteConfigs: [RemoteConfig]

        init(remoteConfigs: [RemoteConfig]) {
            self.remoteConfigs = remoteConfigs
        }

        func remoteConfig(forContextKey key: String) -> RemoteConfig? {
            return findRemoteConfig(forContextKey: key)
        }

        func remoteConfigForEmptyContextKey() -> RemoteConfig? {
            return findRemoteConfig(forContextKey: nil)
        }

        private func findRemoteConfig(forContextKey key: String?) -> RemoteConfig? {
            for config in remoteConfigs {
                if (key == nil && config.source.contextKey == nil) || config.source.contextKey == key {
                    return config
                }
            }
            return nil
        }
    }
}
