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
    // The install's first anonymous uid — logout returns to it.
    case originalUserIdKey = "qonversion.keys.originalUserId"
}

fileprivate enum Constants: String {
    case userIdPrefix = "QON_"
    // The uid keys of the previous production SDK generation.
    case legacyUserIdKey = "com.qonversion.keys.storedUserID"
    case legacyOriginalUserIdKey = "com.qonversion.keys.originalUserID"
    // That generation persisted everything into its own UserDefaults suite,
    // never into the standard/configured one — the migration must read there.
    case legacySuiteName = "qonversion.localstorage.main"
    // The backend's answer (422) to a create carrying a uid it already knows.
    case alreadyExistsApiCode = "already_exists"
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
        let userId: String = internalConfig.userId.isEmpty ? generateUserId() : internalConfig.userId
        do {
            let request = Request.createUser(body: ["id": userId])
            let user: Qonversion.User = try await requestProcessor.process(request: request, responseType: Qonversion.User.self, trigger: RequestTrigger.initialization)

            return user
        } catch {
            // The uid is already taken — which is the normal state of an
            // install upgraded from the previous SDK generation, since it
            // adopts the uid that generation created. The user exists, so the
            // pipeline continues with it instead of failing.
            guard isAlreadyExists(error) else {
                throw QonversionError(type: .userCreationFailed, message: nil, error: error)
            }

            return try await user()
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
            let user: Qonversion.User = try await requestProcessor.process(request: request, responseType: Qonversion.User.self, trigger: RequestTrigger.initialization)
            
            return user
        } catch {
            throw QonversionError(type: .userLoadingFailed, message: nil, error: error)
        }
    }
}

// MARK: - Private

extension UserService {

    /// The conflict arrives wrapped by whichever layer failed, so the whole
    /// error chain is inspected, not only its outermost link.
    private func isAlreadyExists(_ error: Error) -> Bool {
        guard let qonversionError = error as? QonversionError else { return false }
        if qonversionError.apiCode == Constants.alreadyExistsApiCode.rawValue { return true }
        guard let underlying: Error = qonversionError.error else { return false }

        return isAlreadyExists(underlying)
    }

    private func prepareUserId() {
        // An install updated from the previous SDK generation keeps its user:
        // the legacy uid moves to the new storage and the legacy key is cleaned.
        if let legacyUserId: String = consumeLegacyValue(forKey: Constants.legacyUserIdKey.rawValue) {
            localStorage.set(string: legacyUserId, forKey: UserServiceStorageKeys.userIdKey.rawValue)
            internalConfig.userId = legacyUserId
            // An install identified in the previous SDK carries the identified
            // uid as its current one — the TRUE original anonymous uid lives
            // in the production original-user key.
            let legacyOriginalUserId: String? = consumeLegacyValue(forKey: Constants.legacyOriginalUserIdKey.rawValue)
            rememberOriginalUserIdIfNeeded(legacyOriginalUserId ?? legacyUserId)
            return
        }

        let userId: String = localStorage.string(forKey: UserServiceStorageKeys.userIdKey.rawValue) ?? generateUserId()
        internalConfig.userId = userId
        rememberOriginalUserIdIfNeeded(userId)
    }

    /// Reads a key of the previous SDK generation and removes it, so the
    /// migration runs exactly once. The dedicated production suite comes
    /// first; the configured storage is checked as well, since a host app may
    /// have pointed the previous SDK at its own UserDefaults.
    private func consumeLegacyValue(forKey key: String) -> String? {
        let legacyDefaults: UserDefaults? = UserDefaults(suiteName: Constants.legacySuiteName.rawValue)
        if let suiteValue: String = legacyDefaults?.string(forKey: key), !suiteValue.isEmpty {
            legacyDefaults?.removeObject(forKey: key)
            localStorage.removeObject(forKey: key)
            return suiteValue
        }

        if let storageValue: String = localStorage.string(forKey: key), !storageValue.isEmpty {
            localStorage.removeObject(forKey: key)
            return storageValue
        }

        legacyDefaults?.removeObject(forKey: key)
        localStorage.removeObject(forKey: key)
        return nil
    }

    /// The anonymous user this install started with: identity switches move
    /// the uid away, logout must come back — it owns the pre-identify purchases.
    private func rememberOriginalUserIdIfNeeded(_ userId: String) {
        guard localStorage.string(forKey: UserServiceStorageKeys.originalUserIdKey.rawValue) == nil else { return }

        localStorage.set(string: userId, forKey: UserServiceStorageKeys.originalUserIdKey.rawValue)
    }
}
