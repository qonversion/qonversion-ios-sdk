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

// @unchecked: the cache and generation are lock-guarded.
final class RemoteConfigManager: RemoteConfigManagerInterface, @unchecked Sendable {

    private let remoteConfigService: RemoteConfigServiceInterface
    private let logger: LoggerWrapper

    // The cache is read/written from concurrent loads and cleared from the
    // user-change notification thread.
    private let lock = NSLock()
    private var loadedConfigs: [String: Qonversion.RemoteConfig] = [:]

    /// Bumped on every user switch: a load that started for the previous user
    /// must not cache its (stale) response for the new one.
    private var cacheGeneration = 0

    init(remoteConfigService: RemoteConfigServiceInterface, logger: LoggerWrapper) {
        self.remoteConfigService = remoteConfigService
        self.logger = logger
    }

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig {
        let finalKey: String = contextKey ?? Constants.emptyContextKey.rawValue
        let (cached, generation) = cachedConfigAndGeneration(for: finalKey)
        if let cached {
            return cached
        }

        let remoteConfig: Qonversion.RemoteConfig = try await remoteConfigService.loadRemoteConfig(contextKey: contextKey)
        cacheConfig(remoteConfig, for: finalKey, ifGenerationIs: generation)

        return remoteConfig
    }

    private func cachedConfigAndGeneration(for key: String) -> (Qonversion.RemoteConfig?, Int) {
        lock.lock()
        defer { lock.unlock() }
        return (loadedConfigs[key], cacheGeneration)
    }

    private func cacheConfig(_ config: Qonversion.RemoteConfig, for key: String, ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return }
        loadedConfigs[key] = config
    }

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList {
        let generation = currentGeneration()
        let remoteConfigList: Qonversion.RemoteConfigList = try await remoteConfigService.loadRemoteConfigList()
        handleLoadedRemoteConfigList(remoteConfigList, generation: generation)
        return remoteConfigList
    }

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        let (cachedConfigs, generation) = cachedConfigsAndGeneration(for: contextKeys)
        if (cachedConfigs.count == contextKeys.count) {
            return Qonversion.RemoteConfigList(remoteConfigs: cachedConfigs)
        }
        let remoteConfigList: Qonversion.RemoteConfigList = try await remoteConfigService.loadRemoteConfigList(contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
        handleLoadedRemoteConfigList(remoteConfigList, generation: generation)
        return remoteConfigList
    }

    func attachUserToRemoteConfig(id: String) async throws {
        try await remoteConfigService.attachUserToRemoteConfig(id: id)
    }

    func detachUserFromRemoteConfig(id: String) async throws {
        try await remoteConfigService.detachUserFromRemoteConfig(id: id)
    }

    func attachUserToExperiment(id: String, groupId: String) async throws {
        try await remoteConfigService.attachUserToExperiment(id: id, groupId: groupId)
    }

    func detachUserFromExperiment(id: String) async throws {
        try await remoteConfigService.detachUserFromExperiment(id: id)
    }
    
    // MARK: - Private

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cacheGeneration
    }

    private func cachedConfigsAndGeneration(for contextKeys: [String]) -> ([Qonversion.RemoteConfig], Int) {
        lock.lock()
        defer { lock.unlock() }
        return (contextKeys.compactMap { loadedConfigs[$0] }, cacheGeneration)
    }

    private func handleLoadedRemoteConfigList(_ remoteConfigList: Qonversion.RemoteConfigList, generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard generation == cacheGeneration else { return }

        remoteConfigList.remoteConfigs.forEach { remoteConfig in
            let contextKey: String = remoteConfig.source.contextKey ?? Constants.emptyContextKey.rawValue
            loadedConfigs[contextKey] = remoteConfig
        }
    }
}

// MARK: - UserChangedObserver

extension RemoteConfigManager: UserChangedObserver {

    func userDidChange() {
        lock.lock()
        defer { lock.unlock() }

        cacheGeneration += 1
        loadedConfigs = [:]
    }
}
