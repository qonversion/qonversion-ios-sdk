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

    /// Bumped by logout: a pipeline or identity continuation that resumes
    /// after the bump belongs to the previous session and must not touch
    /// the state of the new one.
    private var sessionGeneration = 0

    fileprivate struct PipelineOutcome: Sendable {
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
        // The generation guards inside the pipeline throw CancellationError,
        // a Swift runtime type. This is a public entry point, so it is
        // classified here — the host is documented to catch QonversionError.
        do {
            let outcome: PipelineOutcome = try await runPipeline()

            return currentUser() ?? outcome.user
        } catch {
            throw error.classifiedForPublicAPI
        }
    }

    @discardableResult
    func identify(_ externalId: String) async throws -> Qonversion.User {
        // Already linked to this external id: answer locally, like production —
        // an identify on every launch must not cost two requests.
        if identifyInFlight == nil,
           let user: Qonversion.User = existingUser(),
           localStorage.string(forKey: Constants.identityKey.rawValue) == externalId {
            return user
        }

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
                let outcome: PipelineOutcome = try await self.runPipeline()
                if let identityError: Error = outcome.identityError {
                    throw identityError
                }
                // A joined pipeline may have passed its identity step before
                // this registration — the pending id would dangle silently.
                if self.pendingIdentityExternalId == externalId {
                    self.pendingIdentityExternalId = nil
                    _ = try await self.linkIdentity(externalId)
                }
                return self.currentUser() ?? outcome.user
            }
        }
        identifyInFlight = (flightId, externalId, task)

        defer {
            if identifyInFlight?.id == flightId {
                identifyInFlight = nil
            }
        }

        do {
            return try await task.value
        } catch {
            throw error.classifiedForPublicAPI
        }
    }

    func logout() async {
        // The identity teardown is unconditional: an identify in flight (or
        // pending) at logout time must never settle afterwards — even when
        // the uid has not moved yet, which is exactly the first-identify case.
        sessionGeneration += 1
        pipeline?.cancel()
        pipeline = nil
        pendingIdentityExternalId = nil
        identifyInFlight?.task.cancel()
        identifyInFlight = nil
        localStorage.removeObject(forKey: Constants.identityKey.rawValue)

        // Production semantics: the uid restore (and the cache wipe it
        // implies) only happens when the uid actually moved away from the
        // install's original anonymous user.
        let originalUid: String? = localStorage.string(forKey: UserServiceStorageKeys.originalUserIdKey.rawValue)
        guard let originalUid, !originalUid.isEmpty, originalUid != internalConfig.userId else { return }

        // The last moment at which data queued by the user being logged out
        // can still leave under their uid.
        await userChangesNotifier.notifyUserWillChange()

        cachedUser = nil
        localStorage.removeObject(forKey: Constants.userKey.rawValue)

        // Back to the original anonymous user — it owns the purchases made
        // before identify; minting a fresh uid would orphan them.
        internalConfig.userId = originalUid
        localStorage.set(string: originalUid, forKey: UserServiceStorageKeys.userIdKey.rawValue)

        userChangesNotifier.notifyUserChanged()
    }

    func switchToUser(with uid: String) async throws {
        guard uid != internalConfig.userId else { return }

        do {
            try await switchUser(to: uid)
        } catch {
            throw error.classifiedForPublicAPI
        }
    }

    /// Waits until no identify is in flight and the creation pipeline has
    /// settled — user-scoped requests (remote config) must not race a uid switch.
    func awaitUserStability() async throws {
        var identifyError: Error?
        while let inFlight = identifyInFlight {
            do {
                _ = try await inFlight.task.value
                identifyError = nil
            } catch {
                // A logout cancels the identify on purpose — that is a session
                // teardown, not a failure the caller has to handle.
                identifyError = Self.isCancellation(error) ? nil : error
            }
            if identifyInFlight?.id == inFlight.id {
                identifyInFlight = nil
            }
        }
        // A pipeline failure is not reported here: every caller passes the
        // user gate right after and gets it from there.
        if let pipeline {
            _ = try? await pipeline.value
        }

        if let identifyError { throw identifyError.classifiedForPublicAPI }
    }

    func userInfo() async throws -> Qonversion.User {
        try await obtainUser()

        do {
            let user: Qonversion.User = try await userService.user()
            persist(user)
            cachedUser = user

            return user
        } catch {
            // The ObjC SDK always answered this locally — the user record is
            // persisted on the device. Failing a call that needs no network is
            // a regression the host feels as "who am I?" breaking offline.
            // The error surfaces only when nothing local exists.
            // A cancelled fetch is not an outage: the SDK abandoned it because
            // the user switched, so answering from the (now previous user's)
            // persisted record would be worse than failing.
            guard !error.isCancellation else { throw error.classifiedForPublicAPI }
            guard let local: Qonversion.User = currentUser() else { throw error.classifiedForPublicAPI }

            logger.warning("The user request failed, answering from the persisted user: " + error.message)
            return local
        }
    }

    /// Cancellation reaches the SDK in more than one shape: a task cancelled
    /// while suspended in URLSession surfaces as URLError(.cancelled), wrapped
    /// in the SDK error of the failing layer.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let qonversionError = error as? QonversionError, let underlying: Error = qonversionError.error {
            return isCancellation(underlying)
        }

        return false
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

        if let user: Qonversion.User = existingUser(), pendingIdentityExternalId == nil {
            return PipelineOutcome(user: user, identityError: nil)
        }

        let task = Task<PipelineOutcome, Error> {
            let generation: Int = self.sessionGeneration
            let user: Qonversion.User
            if let existing: Qonversion.User = existingUser() {
                user = existing
            } else {
                user = try await userService.createUser()
                // A logout landed while the request was in flight — the
                // created user belongs to the previous session.
                guard generation == self.sessionGeneration else { throw CancellationError() }
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
            let outcome: PipelineOutcome = try await task.value
            // Only ITS OWN task may be cleared: a successor started while this
            // one was settling must stay the current pipeline.
            if pipeline == task {
                pipeline = nil
            }
            return outcome
        } catch {
            if pipeline == task {
                pipeline = nil
            }
            throw error
        }
    }

    /// Links the external id to the current user. When the external id is
    /// already linked to another Qonversion user, switches to that user.
    func linkIdentity(_ externalId: String) async throws -> Qonversion.User {
        let generation: Int = sessionGeneration
        let currentUid: String = internalConfig.userId

        if let linkedUid = try await userService.identity(for: externalId) {
            // A logout landed mid-flight: applying the link now would silently
            // re-identify the user the host just logged out.
            guard generation == sessionGeneration else { throw CancellationError() }
            if linkedUid != currentUid {
                try await switchUser(to: linkedUid, identityExternalId: externalId)
                return try currentUserOrFail()
            }
        } else {
            guard generation == sessionGeneration else { throw CancellationError() }
            let resultUid: String = try await userService.createIdentity(externalId: externalId, userId: currentUid)
            guard generation == sessionGeneration else { throw CancellationError() }
            if resultUid != currentUid {
                try await switchUser(to: resultUid, identityExternalId: externalId)
                return try currentUserOrFail()
            }
        }

        localStorage.set(string: externalId, forKey: Constants.identityKey.rawValue)

        return try currentUserOrFail()
    }

    func currentUserOrFail() throws -> Qonversion.User {
        guard let user = currentUser() else {
            throw QonversionError(type: .userLoadingFailed)
        }

        return user
    }

    /// Switches the SDK to another Qonversion user (identity owner). The
    /// identity that caused the switch is persisted WITH the uid: a throwing
    /// user fetch must not leave the new uid stored without its identity.
    func switchUser(to uid: String, identityExternalId: String? = nil) async throws {
        let generation: Int = sessionGeneration

        // Data queued under the outgoing uid leaves before the swap; the
        // request path reads the uid at send time, so afterwards it is too late.
        await userChangesNotifier.notifyUserWillChange()
        // A logout landed while the flush was running: the switch belongs to
        // the session the host just ended.
        guard generation == sessionGeneration else { throw CancellationError() }

        internalConfig.userId = uid
        localStorage.set(string: uid, forKey: UserServiceStorageKeys.userIdKey.rawValue)
        if let identityExternalId {
            localStorage.set(string: identityExternalId, forKey: Constants.identityKey.rawValue)
        }

        // The cleared caches belong to the previous user — clear right after
        // the uid switch, so a failed user fetch cannot leak them to the new uid.
        userChangesNotifier.notifyUserChanged()

        let user: Qonversion.User = try await userService.user()
        // A logout landed while the user was loading: caching it now would
        // resurrect the session the host just ended.
        guard generation == sessionGeneration else { throw CancellationError() }

        cachedUser = user
        persist(user)
    }

    func currentUser() -> Qonversion.User? {
        if let cachedUser, cachedUser.id == internalConfig.userId {
            return cachedUser
        }
        return persistedUser()
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
