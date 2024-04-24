//
//  RemoteConfigManager.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

fileprivate enum Constants: String {
    case emptyContextKey = ""
}

final class RemoteConfigManager: RemoteConfigManagerInterface {

    private let remoteConfigService: RemoteConfigServiceInterface
    private let logger: LoggerWrapper
    private var loadedConfigs: [String: Qonversion.RemoteConfig] = [:]

    init(remoteConfigService: RemoteConfigServiceInterface, logger: LoggerWrapper) {
        self.remoteConfigService = remoteConfigService
        self.logger = logger
    }

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig {
        let finalKey: String = contextKey ?? Constants.emptyContextKey.rawValue
        if let cachedConfig: Qonversion.RemoteConfig = loadedConfigs[finalKey] {
            return cachedConfig
        }

        let remoteConfig: Qonversion.RemoteConfig = try await remoteConfigService.loadRemoteConfig(contextKey: contextKey)
        loadedConfigs[finalKey] = remoteConfig

        return remoteConfig
    }

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList {
        let remoteConfigList: Qonversion.RemoteConfigList = try await remoteConfigService.loadRemoteConfigList()
        handleLoadedRemoteConfigList(remoteConfigList)
        return remoteConfigList
    }

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        let cachedConfigs = contextKeys.compactMap { self.loadedConfigs[$0] }
        if (cachedConfigs.count == contextKeys.count) {
            return Qonversion.RemoteConfigList(remoteConfigs: cachedConfigs)
        }

        let remoteConfigList: Qonversion.RemoteConfigList = try await remoteConfigService.loadRemoteConfigList(contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
        handleLoadedRemoteConfigList(remoteConfigList)
        return remoteConfigList
    }

    func attachUserToRemoteConfig(remoteConfigId: String) async -> Bool {
        do {
            return try await remoteConfigService.attachUserToRemoteConfig(remoteConfigId: remoteConfigId)
        } catch {
            return false
        }
    }

    func detachUserFromRemoteConfig(remoteConfigId: String) async -> Bool {
        do {
            return try await remoteConfigService.detachUserFromRemoteConfig(remoteConfigId: remoteConfigId)
        } catch {
            return false
        }
    }

    func attachUserToExperiment(experimentId: String, groupId: String) async -> Bool {
        do {
            return try await remoteConfigService.attachUserToExperiment(experimentId: experimentId, groupId: groupId)
        } catch {
            return false
        }
    }

    func detachUserFromExperiment(experimentId: String) async -> Bool {
        do {
            return try await remoteConfigService.detachUserFromExperiment(experimentId: experimentId)
        } catch {
            return false
        }
    }
    
    // MARK: - Private

    private func handleLoadedRemoteConfigList(_ remoteConfigList: Qonversion.RemoteConfigList) {
        remoteConfigList.remoteConfigs.forEach { remoteConfig in
            let contextKey: String = remoteConfig.source.contextKey ?? Constants.emptyContextKey.rawValue
            loadedConfigs[contextKey] = remoteConfig
        }
    }
}
