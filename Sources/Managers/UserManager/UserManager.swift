//
//  UserManager.swift
//  Qonversion
//

import Foundation

fileprivate enum Constants: String {
    case userKey = "qonversion.keys.user"
    case identityKey = "qonversion.keys.identityExternalId"
}

/// The user lifecycle gate. An actor: all state transitions are serialized,
/// so user creation is single-flight by construction — concurrent callers
/// share one in-flight pipeline task and receive the same user.
actor UserManager: UserManagerInterface {

    private let userService: UserServiceInterface
    private let localStorage: LocalStorageInterface
    private let internalConfig: InternalConfig
    private let userChangesNotifier: UserChangesNotifierInterface
    private let logger: LoggerWrapper

    /// The shared "promise": creation of the backend user plus, when an
    /// identify is pending, the identity request. Waiters await this task and
    /// resume only after both have finished.
    private var pipeline: Task<PipelineOutcome, Error>?
    private var cachedUser: Qonversion.User?
    private var pendingIdentityExternalId: String?

    /// The in-flight identify: a call with the same external id joins it, a
    /// call with a different id waits for it to settle and then runs its own.
    private var identifyInFlight: (id: UUID, externalId: String, task: Task<Qonversion.User, Error>)?

    fileprivate struct PipelineOutcome {
        let user: Qonversion.User
        /// A pending-identity failure is delivered to the identify caller only;
        /// data-sending waiters proceed with the created user.
        let identityError: Error?
    }

    init(userService: UserServiceInterface, localStorage: LocalStorageInterface, internalConfig: InternalConfig, userChangesNotifier: UserChangesNotifierInterface, logger: LoggerWrapper) {
        self.userService = userService
        self.localStorage = localStorage
        self.internalConfig = internalConfig
        self.userChangesNotifier = userChangesNotifier
        self.logger = logger
    }

    @discardableResult
    func obtainUser() async throws -> Qonversion.User {
        let outcome = try await runPipeline()

        return currentUser() ?? outcome.user
    }

    @discardableResult
    func identify(_ externalId: String) async throws -> Qonversion.User {
        while let inFlight = identifyInFlight {
            if inFlight.externalId == externalId {
                return try await inFlight.task.value
            }
            // A different id: let the in-flight one settle first, then re-check.
            // The settled marker is cleared here as well — awaiting an
            // already-finished task may not suspend, and waiting for the
            // owner to clear it would livelock the actor.
            _ = try? await inFlight.task.value
            if identifyInFlight?.id == inFlight.id {
                identifyInFlight = nil
            }
        }

        let flightId = UUID()
        // The branch decision and the pending-identity registration happen
        // synchronously in THIS actor turn: a pipeline started by a concurrent
        // obtainUser must not slip in without the pending identity.
        let task: Task<Qonversion.User, Error>
        if existingUser() != nil && pipeline == nil {
            task = Task { try await self.linkIdentity(externalId) }
        } else {
            pendingIdentityExternalId = externalId
            task = Task {
                let outcome = try await self.runPipeline()
                if let identityError = outcome.identityError {
                    throw identityError
                }
                return await self.currentUser() ?? outcome.user
            }
        }
        identifyInFlight = (flightId, externalId, task)

        defer {
            if identifyInFlight?.id == flightId {
                identifyInFlight = nil
            }
        }

        return try await task.value
    }

    func logout() async {
        pipeline?.cancel()
        pipeline = nil
        pendingIdentityExternalId = nil
        cachedUser = nil
        localStorage.removeObject(forKey: Constants.userKey.rawValue)
        localStorage.removeObject(forKey: Constants.identityKey.rawValue)

        // A fresh anonymous uid; the backend user is created lazily on the next demand.
        _ = userService.generateUserId()

        userChangesNotifier.notifyUserChanged()
    }

    func userInfo() async throws -> Qonversion.User {
        try await obtainUser()

        return try await userService.user()
    }
}

// MARK: - Private

private extension UserManager {

    /// Single-flight: the first caller starts the pipeline, everyone else
    /// awaits the same task. On failure the pipeline resets so the next
    /// demand retries.
    func runPipeline() async throws -> PipelineOutcome {
        if let pipeline {
            return try await pipeline.value
        }

        if let user = existingUser(), pendingIdentityExternalId == nil {
            return PipelineOutcome(user: user, identityError: nil)
        }

        let task = Task<PipelineOutcome, Error> {
            let user: Qonversion.User
            if let existing = existingUser() {
                user = existing
            } else {
                user = try await userService.createUser()
                cachedUser = user
                persist(user)
            }

            var identityError: Error?
            if let externalId = pendingIdentityExternalId {
                pendingIdentityExternalId = nil
                do {
                    _ = try await linkIdentity(externalId)
                } catch {
                    identityError = error
                }
            }

            return PipelineOutcome(user: currentUser() ?? user, identityError: identityError)
        }

        pipeline = task
        do {
            let outcome = try await task.value
            pipeline = nil
            return outcome
        } catch {
            pipeline = nil
            throw error
        }
    }

    /// Links the external id to the current user. When the external id is
    /// already linked to another Qonversion user, switches to that user.
    func linkIdentity(_ externalId: String) async throws -> Qonversion.User {
        let currentUid = internalConfig.userId

        if let linkedUid = try await userService.identity(for: externalId) {
            if linkedUid != currentUid {
                try await switchUser(to: linkedUid)
            }
        } else {
            let resultUid = try await userService.createIdentity(externalId: externalId, userId: currentUid)
            if resultUid != currentUid {
                try await switchUser(to: resultUid)
            }
        }

        localStorage.set(string: externalId, forKey: Constants.identityKey.rawValue)

        guard let user = currentUser() else {
            throw QonversionError(type: .userLoadingFailed)
        }
        return user
    }

    /// Switches the SDK to another Qonversion user (identity owner).
    func switchUser(to uid: String) async throws {
        internalConfig.userId = uid
        localStorage.set(string: uid, forKey: UserServiceStorageKeys.userIdKey.rawValue)

        // The cleared caches belong to the previous user — clear right after
        // the uid switch, so a failed user fetch cannot leak them to the new uid.
        userChangesNotifier.notifyUserChanged()

        let user = try await userService.user()
        cachedUser = user
        persist(user)
    }

    func currentUser() -> Qonversion.User? {
        return cachedUser ?? persistedUser()
    }

    /// The user is considered created when a persisted user matching the
    /// current uid exists (or one is cached in memory).
    func existingUser() -> Qonversion.User? {
        if let cachedUser, cachedUser.id == internalConfig.userId {
            return cachedUser
        }
        if let persisted = persistedUser() {
            cachedUser = persisted
            return persisted
        }
        return nil
    }

    func persistedUser() -> Qonversion.User? {
        guard let user = try? localStorage.object(forKey: Constants.userKey.rawValue, dataType: Qonversion.User.self),
              user.id == internalConfig.userId else { return nil }
        return user
    }

    func persist(_ user: Qonversion.User) {
        do {
            try localStorage.set(user, forKey: Constants.userKey.rawValue)
        } catch {
            logger.error("Failed to persist user: " + error.message)
        }
    }
}
