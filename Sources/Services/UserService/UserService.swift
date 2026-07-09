//
//  UserService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

/// Storage keys shared between UserService and the user gate (UserManager).
enum UserServiceStorageKeys: String {
    case userIdKey = "qonversion.keys.userId"
}

fileprivate enum Constants: String {
    case userIdPrefix = "QON_"
    // The uid key of the previous production SDK generation.
    case legacyUserIdKey = "com.qonversion.keys.storedUserID"
}

// @unchecked: stateless — every dependency is thread-safe on its own.
final class UserService: UserServiceInterface, @unchecked Sendable {
    
    private let requestProcessor: RequestProcessorInterface
    private let localStorage: LocalStorageInterface
    private let internalConfig: InternalConfig
    
    init(requestProcessor: RequestProcessorInterface, localStorage: LocalStorageInterface, internalConfig: InternalConfig) {
        self.requestProcessor = requestProcessor
        self.localStorage = localStorage
        self.internalConfig = internalConfig
        
        prepareUserId()
    }
    
    func generateUserId() -> String {
        let uuidString: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let userId: String = Constants.userIdPrefix.rawValue + uuidString.lowercased()
        localStorage.set(string: userId, forKey: UserServiceStorageKeys.userIdKey.rawValue)
        internalConfig.userId = userId
        
        return userId
    }
    
    func createUser() async throws -> Qonversion.User {
        // The backend upserts by uid: a fresh install creates the user, a
        // migrated install gets its existing user back.
        let userId: String = internalConfig.userId.isEmpty ? generateUserId() : internalConfig.userId
        do {
            // The contract requires the environment field; sandbox/prod
            // separation is not a client-side concern.
            let request = Request.createUser(body: ["id": userId, "environment": "prod"])
            let user: Qonversion.User = try await requestProcessor.process(request: request, responseType: Qonversion.User.self)
            
            return user
        } catch {
            throw QonversionError(type: .userCreationFailed, message: nil, error: error)
        }
    }
    
    func identity(for externalId: String) async throws -> String? {
        let request = Request.getIdentity(externalId: externalId)
        do {
            let identity: Qonversion.Identity = try await requestProcessor.process(request: request, responseType: Qonversion.Identity.self)

            return identity.userId
        } catch {
            if let qonversionError = error as? QonversionError,
               qonversionError.additionalInfo?[ErrorConstants.statusCodeKey.rawValue] as? Int == 404 {
                return nil
            }
            throw QonversionError(type: .identityLoadingFailed, message: nil, error: error)
        }
    }

    func createIdentity(externalId: String, userId: String) async throws -> String {
        let request = Request.createIdentity(body: ["identity_id": externalId, "user_id": userId])
        do {
            let identity: Qonversion.Identity = try await requestProcessor.process(request: request, responseType: Qonversion.Identity.self)

            return identity.userId ?? userId
        } catch {
            throw QonversionError(type: .identityCreationFailed, message: nil, error: error)
        }
    }

    func user() async throws -> Qonversion.User {
        let request = Request.getUser(id: internalConfig.userId)
        do {
            let user: Qonversion.User = try await requestProcessor.process(request: request, responseType: Qonversion.User.self)
            
            return user
        } catch {
            throw QonversionError(type: .userLoadingFailed, message: nil, error: error)
        }
    }
}

// MARK: - Private

extension UserService {
    
    private func prepareUserId() {
        // An install updated from the previous SDK generation keeps its user:
        // the legacy uid moves to the new storage and the legacy key is cleaned.
        if let legacyUserId = localStorage.string(forKey: Constants.legacyUserIdKey.rawValue), !legacyUserId.isEmpty {
            localStorage.set(string: legacyUserId, forKey: UserServiceStorageKeys.userIdKey.rawValue)
            localStorage.removeObject(forKey: Constants.legacyUserIdKey.rawValue)
            internalConfig.userId = legacyUserId
            return
        }

        let userId: String = localStorage.string(forKey: UserServiceStorageKeys.userIdKey.rawValue) ?? generateUserId()
        internalConfig.userId = userId
    }
}
