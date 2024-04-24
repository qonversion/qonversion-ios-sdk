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

    func attachUserToRemoteConfig(id: String) async throws

    func detachUserFromRemoteConfig(id: String) async throws

    func attachUserToExperiment(id: String, groupId: String) async throws

    func detachUserFromExperiment(id: String) async throws
}
