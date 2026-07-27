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
    private let userManager: UserManagerInterface
    private let userPropertiesManager: UserPropertiesManagerInterface
    private let fallbackService: FallbackServiceInterface
    private let logger: LoggerWrapper

    // The cache is read/written from concurrent loads and cleared from the
    // user-change notification thread.
    private let lock = NSLock()
    private var loadedConfigs: [String: Qonversion.RemoteConfig] = [:]

    /// Bumped on every user switch: a load that started for the previous user
    /// must not cache its (stale) response for the new one.
    private var cacheGeneration = 0

    /// One in-flight load per context key: N concurrent callers share a single
    /// request instead of racing each other into the rate limiter.
    private var loadTasks: [String: Task<Qonversion.RemoteConfig, Error>] = [:]

    init(remoteConfigService: RemoteConfigServiceInterface, userManager: UserManagerInterface, userPropertiesManager: UserPropertiesManagerInterface, fallbackService: FallbackServiceInterface, logger: LoggerWrapper) {
        self.remoteConfigService = remoteConfigService
        self.userManager = userManager
        self.userPropertiesManager = userPropertiesManager
        self.fallbackService = fallbackService
        self.logger = logger
    }

    /// Production's "user stability" rule: a config requested while an
    /// identify is switching the uid would belong to the previous user, so the
    /// gate runs before anything is served — the cache included.
    private func awaitUserStability() async throws {
        try await userManager.awaitUserStability()
    }

    /// Remote configs are computed per user from fresh segmentation data: the
    /// pending properties batch must reach the backend before the config is
    /// computed. A flush failure is not fatal — properties retry on their own
    /// schedule.
    private func prepareUserForRemoteConfig() async throws {
        _ = try await userManager.obtainUser()
        try? await userPropertiesManager.sendProperties(force: true)
    }

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig {
        let finalKey: String = contextKey ?? Constants.emptyContextKey.rawValue

        do {
            try await awaitUserStability()

            if let cached: Qonversion.RemoteConfig = cachedConfig(for: finalKey) {
                return cached
            }

            let task: Task<Qonversion.RemoteConfig, Error> = joinedLoadTask(for: finalKey, contextKey: contextKey)
            defer { clearLoadTask(task, for: finalKey) }

            return try await task.value
        } catch {
            guard error.allowsLocalEntitlementsFallback, let fallback: Qonversion.RemoteConfig = fallbackRemoteConfig(for: finalKey) else { throw error }

            logger.warning("Remote config request failed, using the bundled fallback file: " + error.message)
            return fallback
        }
    }

    private func joinedLoadTask(for key: String, contextKey: String?) -> Task<Qonversion.RemoteConfig, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let inFlight: Task<Qonversion.RemoteConfig, Error> = loadTasks[key] {
            return inFlight
        }

        let task = Task { [weak self] () throws -> Qonversion.RemoteConfig in
            guard let self else { throw QonversionError.initializationError() }

            try await self.prepareUserForRemoteConfig()

            // Snapshotted right before the request, like every other loader.
            let generation: Int = self.currentGeneration()
            let remoteConfig: Qonversion.RemoteConfig = try await self.remoteConfigService.loadRemoteConfig(contextKey: contextKey)
            self.cacheConfig(remoteConfig, for: key, ifGenerationIs: generation)

            return remoteConfig
        }
        loadTasks[key] = task

        return task
    }

    private func clearLoadTask(_ task: Task<Qonversion.RemoteConfig, Error>, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if loadTasks[key] == task {
            loadTasks[key] = nil
        }
    }

    private func cachedConfig(for key: String) -> Qonversion.RemoteConfig? {
        lock.lock()
        defer { lock.unlock() }
        return loadedConfigs[key]
    }

    private func cacheConfig(_ config: Qonversion.RemoteConfig, for key: String, ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return }
        loadedConfigs[key] = config
    }

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList {
        do {
            try await awaitUserStability()
            try await prepareUserForRemoteConfig()

            let generation: Int = currentGeneration()
            let remoteConfigList: Qonversion.RemoteConfigList = try await remoteConfigService.loadRemoteConfigList()
            handleLoadedRemoteConfigList(remoteConfigList, generation: generation)
            return remoteConfigList
        } catch {
            guard error.allowsLocalEntitlementsFallback, let configs: [Qonversion.RemoteConfig] = fallbackService.obtainFallbackData()?.remoteConfigs else { throw error }

            logger.warning("Remote config list request failed, using the bundled fallback file: " + error.message)
            return Qonversion.RemoteConfigList(remoteConfigs: configs)
        }
    }

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        // The empty-context config participates in the cache check when
        // requested; duplicate keys must not fake a full hit.
        var requestedKeys: [String] = []
        for key in contextKeys where !requestedKeys.contains(key) {
            requestedKeys.append(key)
        }
        if includeEmptyContextKey && !requestedKeys.contains(Constants.emptyContextKey.rawValue) {
            requestedKeys.append(Constants.emptyContextKey.rawValue)
        }

        do {
            try await awaitUserStability()

            let cachedConfigs: [Qonversion.RemoteConfig] = cachedConfigs(for: requestedKeys)
            if (cachedConfigs.count == requestedKeys.count) {
                return Qonversion.RemoteConfigList(remoteConfigs: cachedConfigs)
            }

            try await prepareUserForRemoteConfig()

            let generation: Int = currentGeneration()
            let remoteConfigList: Qonversion.RemoteConfigList = try await remoteConfigService.loadRemoteConfigList(contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
            handleLoadedRemoteConfigList(remoteConfigList, generation: generation)
            return remoteConfigList
        } catch {
            guard error.allowsLocalEntitlementsFallback, let allConfigs: [Qonversion.RemoteConfig] = fallbackService.obtainFallbackData()?.remoteConfigs else { throw error }

            logger.warning("Remote config list request failed, using the bundled fallback file: " + error.message)
            let matching: [Qonversion.RemoteConfig] = allConfigs.filter { config in
                if let contextKey: String = config.source.contextKey {
                    return contextKeys.contains(contextKey)
                }
                return includeEmptyContextKey
            }
            return Qonversion.RemoteConfigList(remoteConfigs: matching)
        }
    }

    func attachUserToRemoteConfig(id: String) async throws {
        _ = try await userManager.obtainUser()
        try await remoteConfigService.attachUserToRemoteConfig(id: id)
        invalidateCache()
    }

    func detachUserFromRemoteConfig(id: String) async throws {
        _ = try await userManager.obtainUser()
        try await remoteConfigService.detachUserFromRemoteConfig(id: id)
        invalidateCache()
    }

    func attachUserToExperiment(id: String, groupId: String) async throws {
        _ = try await userManager.obtainUser()
        try await remoteConfigService.attachUserToExperiment(id: id, groupId: groupId)
        invalidateCache()
    }

    func detachUserFromExperiment(id: String) async throws {
        _ = try await userManager.obtainUser()
        try await remoteConfigService.detachUserFromExperiment(id: id)
        invalidateCache()
    }

    /// Attach/detach exist to CHANGE the user's configs — serving the cached
    /// ones afterwards would defeat the call.
    private func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        // The generation bump keeps an in-flight pre-attach response from
        // repopulating the cache it just cleared.
        cacheGeneration += 1
        loadedConfigs = [:]
    }
    
    // MARK: - Private

    /// The bundled config for the context key ("" is the empty-key config).
    private func fallbackRemoteConfig(for key: String) -> Qonversion.RemoteConfig? {
        guard let configs: [Qonversion.RemoteConfig] = fallbackService.obtainFallbackData()?.remoteConfigs else { return nil }

        return configs.first { ($0.source.contextKey ?? Constants.emptyContextKey.rawValue) == key }
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cacheGeneration
    }

    private func cachedConfigs(for contextKeys: [String]) -> [Qonversion.RemoteConfig] {
        lock.lock()
        defer { lock.unlock() }
        return contextKeys.compactMap { loadedConfigs[$0] }
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
        cacheGeneration += 1
        loadedConfigs = [:]
        // The in-flight loads belong to the previous user: the generation guard
        // stops them from CACHING their answer, but a caller joining after the
        // switch would still be handed it.
        let abandoned: [Task<Qonversion.RemoteConfig, Error>] = Array(loadTasks.values)
        loadTasks = [:]
        lock.unlock()

        abandoned.forEach { $0.cancel() }
    }
}
