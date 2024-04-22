//
//  RemoteConfigService.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

class RemoteConfigService: RemoteConfigServiceInterface {

    private let requestProcessor: RequestProcessorInterface
    private let userIdProvider: UserIdProvider
    private let logger: LoggerWrapper

    init(requestProcessor: RequestProcessorInterface, userIdProvider: UserIdProvider, logger: LoggerWrapper) {
        self.requestProcessor = requestProcessor
        self.userIdProvider = userIdProvider
        self.logger = logger
    }

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig {
        do {
            let request = Request.remoteConfig(userId: userIdProvider.getUserId(), contextKey: contextKey)
            let remoteConfig: Qonversion.RemoteConfig = try await requestProcessor.process(request: request, responseType: Qonversion.RemoteConfig.self)

            return remoteConfig
        } catch {
            let qonversionError = QonversionError(type: .loadingRemoteConfigFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList {
        do {
            let request = Request.allRemoteConfigList(userId: userIdProvider.getUserId())
            let remoteConfigs: [Qonversion.RemoteConfig] = try await requestProcessor.process(request: request, responseType: [Qonversion.RemoteConfig].self)
            let remoteConfigList: Qonversion.RemoteConfigList = Qonversion.RemoteConfigList(remoteConfigs: remoteConfigs)

            return remoteConfigList
        } catch {
            let qonversionError = QonversionError(type: .loadingRemoteConfigListFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        do {
            let request = Request.remoteConfigList(userId: userIdProvider.getUserId(), contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
            let remoteConfigs: [Qonversion.RemoteConfig] = try await requestProcessor.process(request: request, responseType: [Qonversion.RemoteConfig].self)
            let remoteConfigList: Qonversion.RemoteConfigList = Qonversion.RemoteConfigList(remoteConfigs: remoteConfigs)

            return remoteConfigList
        } catch {
            let qonversionError = QonversionError(type: .loadingRemoteConfigListFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }

    func attachUserToRemoteConfig(remoteConfigId: String) async throws -> Bool {
        do {
            let request = Request.attachUserToRemoteConfig(userId: userIdProvider.getUserId(), remoteConfigId: remoteConfigId)
            _ = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)

            return true
        } catch {
            let qonversionError = QonversionError(type: .attachingUserToRemoteConfigFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }

    func detachUserFromRemoteConfig(remoteConfigId: String) async throws -> Bool {
        do {
            let request = Request.detachUserFromRemoteConfig(userId: userIdProvider.getUserId(), remoteConfigId: remoteConfigId)
            _ = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)

            return true
        } catch {
            let qonversionError = QonversionError(type: .detachingUserFromRemoteConfigFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }

    func attachUserToExperiment(experimentId: String, groupId: String) async throws -> Bool {
        do {
            let request = Request.attachUserToExperiment(userId: userIdProvider.getUserId(), experimentId: experimentId, groupId: groupId)
            _ = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)

            return true
        } catch {
            let qonversionError = QonversionError(type: .attachingUserToExperimentFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }

    func detachUserFromExperiment(experimentId: String) async throws -> Bool {
        do {
            let request = Request.detachUserFromExperiment(userId: userIdProvider.getUserId(), experimentId: experimentId)
            _ = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)

            return true
        } catch {
            let qonversionError = QonversionError(type: .detachingUserFromExperimentFailed, message: nil, error: error)
            logger.warning(qonversionError.message)
            throw qonversionError
        }
    }
}
