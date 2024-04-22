//
//  RemoteConfigServiceInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

protocol RemoteConfigServiceInterface {

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList

    func attachUserToRemoteConfig(remoteConfigId: String) async throws -> Bool

    func detachUserFromRemoteConfig(remoteConfigId: String) async throws -> Bool

    func attachUserToExperiment(experimentId: String, groupId: String) async throws -> Bool

    func detachUserFromExperiment(experimentId: String) async throws -> Bool
}
