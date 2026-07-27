//
//  RemoteConfigService.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

final class RemoteConfigService: RemoteConfigServiceInterface {

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
            let request: Request = Request.remoteConfig(userId: userIdProvider.getUserId(), contextKey: contextKey)
            let remoteConfig: Qonversion.RemoteConfig = try await requestProcessor.process(request: request, responseType: Qonversion.RemoteConfig.self)

            return remoteConfig
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .loadingRemoteConfigFailed)
        }
    }

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList {
        do {
            let request: Request = Request.allRemoteConfigList(userId: userIdProvider.getUserId())
            // Decoded through the lossy container: one malformed configuration
            // must not cost the caller every other one in the list.
            let remoteConfigList: Qonversion.RemoteConfigList = try await requestProcessor.process(request: request, responseType: Qonversion.RemoteConfigList.self)

            return remoteConfigList
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .loadingRemoteConfigListFailed)
        }
    }

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        do {
            let request: Request = Request.remoteConfigList(userId: userIdProvider.getUserId(), contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
            let remoteConfigList: Qonversion.RemoteConfigList = try await requestProcessor.process(request: request, responseType: Qonversion.RemoteConfigList.self)

            return remoteConfigList
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .loadingRemoteConfigListFailed)
        }
    }

    func attachUserToRemoteConfig(id: String) async throws {
        do {
            let request: Request = Request.attachUserToRemoteConfig(userId: userIdProvider.getUserId(), remoteConfigId: id)
            try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .attachingUserToRemoteConfigFailed, asWarning: true)
        }
    }

    func detachUserFromRemoteConfig(id: String) async throws {
        do {
            let request: Request = Request.detachUserFromRemoteConfig(userId: userIdProvider.getUserId(), remoteConfigId: id)
            try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .detachingUserFromRemoteConfigFailed, asWarning: true)
        }
    }

    func attachUserToExperiment(id: String, groupId: String) async throws {
        do {
            let request: Request = Request.attachUserToExperiment(userId: userIdProvider.getUserId(), experimentId: id, groupId: groupId)
            try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .attachingUserToExperimentFailed, asWarning: true)
        }
    }

    func detachUserFromExperiment(id: String) async throws {
        do {
            let request: Request = Request.detachUserFromExperiment(userId: userIdProvider.getUserId(), experimentId: id)
            try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        } catch {
            throw remoteConfigError(from: error, unclassifiedType: .detachingUserFromExperimentFailed, asWarning: true)
        }
    }

    // MARK: - Private

    /// Keeps the classification the network layer already made instead of
    /// flattening every failure into "loading the remote config failed" with
    /// no apiCode and no apiType — the integrator branches on both.
    ///
    /// One contextual remapping: on the remote config endpoints the 404 family
    /// (`not_found` / `relation_not_found`) does not mean "the SDK asked for
    /// something that does not exist", it means this user — or this context
    /// key — has no configuration. That is the ObjC SDK's
    /// QONErrorCodeRemoteConfigurationNotAvailable and a normal state, so it
    /// gets its own type here rather than globally.
    private func remoteConfigError(from error: Error, unclassifiedType: QonversionErrorType, asWarning: Bool = false) -> QonversionError {
        let result: QonversionError = classify(error, unclassifiedType: unclassifiedType)
        if asWarning {
            logger.warning(result.message)
        } else {
            logger.error(result.message)
        }

        return result
    }

    private func classify(_ error: Error, unclassifiedType: QonversionErrorType) -> QonversionError {
        guard let apiError = error as? QonversionError else {
            return QonversionError(type: unclassifiedType, message: nil, error: error)
        }

        switch apiError.type {
        case .resourceNotFound:
            return QonversionError(
                type: .remoteConfigurationNotAvailable,
                message: nil,
                error: apiError.error,
                additionalInfo: apiError.additionalInfo,
                apiCode: apiError.apiCode,
                apiType: apiError.apiType
            )
        case .unknown:
            // Genuinely unclassifiable: keep the endpoint-specific type, but
            // carry the backend fields through.
            return QonversionError(
                type: unclassifiedType,
                message: nil,
                error: apiError.error,
                additionalInfo: apiError.additionalInfo,
                apiCode: apiError.apiCode,
                apiType: apiError.apiType
            )
        default:
            return apiError
        }
    }
}
