//
//  RemoteConfigManagerInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

protocol RemoteConfigManagerInterface {

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList

    func attachUserToRemoteConfig(remoteConfigId: String) async -> Bool

    func detachUserFromRemoteConfig(remoteConfigId: String) async -> Bool

    func attachUserToExperiment(experimentId: String, groupId: String) async -> Bool

    func detachUserFromExperiment(experimentId: String) async -> Bool
}
