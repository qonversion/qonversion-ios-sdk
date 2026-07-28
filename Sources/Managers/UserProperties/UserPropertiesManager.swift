//
//  UserPropertiesManager.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation
#if canImport(AdServices)
import AdServices
#endif

fileprivate enum StringConstants: String {
    // The provider name the backend expects for AdServices tokens.
    case appleAdServicesProvider = "apple_adservices_token"
}

fileprivate enum Constants: Int {
    case sendPropertiesMinDelaySec = 5
    // After this many failed attempts the batch stays in the storage but the
    // scheduling stops; the next setProperty call re-triggers sending.
    case sendPropertiesMaxRetries = 10
}

// @unchecked: mutable state is guarded by stateLock; deps are thread-safe.
final class UserPropertiesManager : UserPropertiesManagerInterface, @unchecked Sendable {
    
    private let requestProcessor: RequestProcessorInterface
    private let propertiesStorage: PropertiesStorage
    private let delayCalculator: IncrementalDelayCalculator
    private let userIdProvider: UserIdProvider
    private let userManager: UserManagerInterface
    private let integrationsInfoCollector: IntegrationsInfoCollectorInterface
    private let logger: LoggerWrapper
    private let notificationCenter: NotificationCenter

    private let backgroundNotificationName: Notification.Name

    /// Kept so the observer can be removed: a token-less registration lives
    /// as long as the process does, even after the manager is gone.
    private var backgroundObserver: NSObjectProtocol?

    // Mutated from the caller's thread (setProperty) and from the scheduled
    // sending task concurrently.
    private let stateLock = NSLock()
    private var sendingTask: Task<Void, Error>? = nil
    private var sendPropertiesRetryDelay: Int = Constants.sendPropertiesMinDelaySec.rawValue
    private var sendPropertiesRetryCount: Int = 0
    /// The batch round trip currently in flight. Kept as a handle (not a
    /// flag), so a forced send can await it instead of returning early.
    private var sendingInFlight: Task<Bool, Never>? = nil
    
    init(
        requestProcessor: RequestProcessorInterface,
        propertiesStorage: PropertiesStorage,
        delayCalculator: IncrementalDelayCalculator,
        userIdProvider: UserIdProvider,
        userManager: UserManagerInterface,
        integrationsInfoCollector: IntegrationsInfoCollectorInterface,
        logger: LoggerWrapper,
        notificationCenter: NotificationCenter = .default,
        backgroundNotificationName: Notification.Name = UserPropertiesManager.backgroundNotificationName
    ) {
        self.requestProcessor = requestProcessor
        self.propertiesStorage = propertiesStorage
        self.delayCalculator = delayCalculator
        self.userIdProvider = userIdProvider
        self.userManager = userManager
        self.integrationsInfoCollector = integrationsInfoCollector
        self.logger = logger
        self.notificationCenter = notificationCenter
        self.backgroundNotificationName = backgroundNotificationName

        subscribeToBackgroundFlush()
    }

    deinit {
        if let backgroundObserver {
            notificationCenter.removeObserver(backgroundObserver)
        }
    }

    /// Which app host the SDK is compiled into. Spelled as data rather than as
    /// a chain of `#if`s around the notification names, so the mapping below
    /// can be asserted for every platform from a test running on any single one.
    enum BackgroundFlushHost {
        /// The watch app runs as an app extension: there is no UIApplication.
        case watchExtension
        /// iOS, tvOS, visionOS and Mac Catalyst.
        case uiKitApplication
        /// A Mac app never enters the background.
        case appKitApplication
        /// Anything else the package compiles for — nothing posts it, the
        /// pending batch simply waits for its delay timer.
        case none
    }

    /// The notification that means "the app is leaving the foreground", per
    /// host. Pure and total: no `#if`, so all four mappings exist in every
    /// build. Spelled as the raw strings the frameworks register, because the
    /// typed constants only exist on the platform that declares them; the
    /// current platform's entry is cross-checked against its typed constant in
    /// the tests.
    static func backgroundFlushNotificationName(for host: BackgroundFlushHost) -> Notification.Name {
        switch host {
        case .watchExtension:
            return Notification.Name("NSExtensionHostDidEnterBackgroundNotification")
        case .uiKitApplication:
            return Notification.Name("UIApplicationDidEnterBackgroundNotification")
        case .appKitApplication:
            // Legacy ObjC parity: the Mac SDK has always flushed on resign
            // active, because a Mac app has no background transition to hook.
            // Every cmd-tab posts it, but a flush only reaches the network when
            // a batch is actually pending, so the chatter is bounded by how
            // often the host writes properties, not by how often the user
            // switches windows.
            return Notification.Name("NSApplicationDidResignActiveNotification")
        case .none:
            return Notification.Name("qonversion.notifications.appDidEnterBackground")
        }
    }

    /// The single place the compile-time platform is consulted: it picks the
    /// input, never the outcome.
    static var currentBackgroundFlushHost: BackgroundFlushHost {
        // watchOS imports UIKit too, but has no UIApplication — it must be
        // matched before the UIKit branch.
        #if os(watchOS)
        return .watchExtension
        #elseif canImport(UIKit)
        return .uiKitApplication
        #elseif canImport(AppKit)
        return .appKitApplication
        #else
        return .none
        #endif
    }

    static var backgroundNotificationName: Notification.Name {
        return backgroundFlushNotificationName(for: currentBackgroundFlushHost)
    }

    /// The pending batch waits on a delay timer that never fires once the
    /// process is suspended — flush it when the app goes to background.
    private func subscribeToBackgroundFlush() {
        backgroundObserver = notificationCenter.addObserver(forName: backgroundNotificationName, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            Task {
                try? await self.sendProperties()
            }
        }
    }

    func collectIntegrationsData() {
        // Adjust/AppsFlyer do not ship on watch and vision — same platform
        // gate as production; the Facebook anonymous id is collected everywhere.
        #if !os(watchOS) && !os(visionOS)
        integrationsInfoCollector.adjustUserId { [weak self] adjustUserId in
            guard let self, let adjustUserId, !adjustUserId.isEmpty else { return }
            self.setUserProperty(key: .adjustAdId, value: adjustUserId)
        }
        if let appsFlyerUserId: String = integrationsInfoCollector.appsFlyerUserId(), !appsFlyerUserId.isEmpty {
            setUserProperty(key: .appsFlyerUserId, value: appsFlyerUserId)
        }
        #endif
        if let facebookAnonymousId: String = integrationsInfoCollector.facebookAnonymousId(), !facebookAnonymousId.isEmpty {
            // The key is intentionally not part of the public UserPropertyKey
            // enum — mirrors the production contract.
            setCustomUserProperty(key: "_q_fb_anon_id", value: facebookAnonymousId)
        }
    }
    
    func collectAppleSearchAdsAttribution() {
        #if canImport(AdServices)
        if #available(iOS 14.3, macOS 11.1, visionOS 1.0, *) {
            do {
                let requestedAt: TimeInterval = Date().timeIntervalSince1970
                let token: String = try AAAttribution.attributionToken()

                processRequest(with: token, requestedAt: requestedAt)
            } catch {
                logger.error("\(LoggerInfoMessages.failedToCollectAppleSearchAdsAttribution.rawValue) \(error)")
            }
        } else {
            logger.warning(LoggerInfoMessages.unableToCollectAppleSearchAdsAttribution.rawValue)
        }
        #else
        logger.warning(LoggerInfoMessages.unableToCollectAppleSearchAdsAttribution.rawValue)
        #endif
    }
    
    func userProperties() async throws -> Qonversion.UserProperties {
        try await userManager.obtainUser()

        let request = Request.getProperties(userId: userIdProvider.getUserId())
        let list: ListEnvelope<Qonversion.UserProperty> = try await requestProcessor.process(request: request, responseType: ListEnvelope<Qonversion.UserProperty>.self)
        let result = Qonversion.UserProperties(list.data)
        return result
    }

    func setUserProperty(key: Qonversion.UserPropertyKey, value: String) {
        guard key != .custom else {
            logger.warning("Can not set user property with the key `.custom`. " +
                    "To set custom user property, use the `setCustomUserProperty` method.")
            return
        }
        
        setCustomUserProperty(key: key.rawValue, value: value)
    }

    func setCustomUserProperty(key: String, value: String) {
        guard !value.isEmpty else { return }
        // The production key contract: latin letters required, plus digits
        // and -_.: — anything else is refused before it reaches the batch.
        guard key.range(of: "(?=.*[a-zA-Z])^[-a-zA-Z0-9_.:]+$", options: .regularExpression) != nil else {
            logger.warning("Invalid user property key \"" + key + "\" — the property is ignored.")
            return
        }

        let userProperty = Qonversion.UserProperty(key: key, value: value)
        propertiesStorage.save(userProperty)

        stateLock.lock()
        let alreadyScheduled: Bool = sendingTask != nil
        let delay: Int = sendPropertiesRetryDelay
        stateLock.unlock()
        guard !alreadyScheduled else { return }

        scheduleSendingProperties(withDelay: delay)
    }

    func sendProperties(force: Bool) async throws {
        guard force else {
            // Single-flight: a batch already in flight covers the current
            // storage snapshot; properties added meanwhile are picked up by
            // the trailing reschedule in performSend.
            guard let task: Task<Bool, Never> = startSendingIfIdle() else { return }

            _ = await task.value
            return
        }

        // Forceful: production waits out the round trip already in flight and
        // then sends whatever is still pending, so the caller can rely on the
        // properties having reached the backend. Only the batch pending on
        // entry is owned by this call — properties set while it runs belong to
        // the next one, and chasing them could loop forever.
        let ownedKeys: Set<String> = Set(propertiesStorage.all().map { $0.key })
        while true {
            if let inFlight: Task<Bool, Never> = currentSendingTask() {
                _ = await inFlight.value
            }

            let remaining: [Qonversion.UserProperty] = propertiesStorage.all().filter { ownedKeys.contains($0.key) }
            guard !remaining.isEmpty else { return }
            guard let task: Task<Bool, Never> = startSendingIfIdle() else {
                // Another sender took the slot between the two calls. Yield so
                // this branch can never spin without suspending.
                await Task.yield()
                continue
            }

            let succeeded: Bool = await task.value
            guard succeeded else { return }
        }
    }

    /// One batch round trip. Returns false when the batch did not reach the
    /// backend — the properties stay in the storage and a retry is scheduled.
    private func performSend() async -> Bool {
        let properties: [Qonversion.UserProperty] = propertiesStorage.all()

        guard !properties.isEmpty else { return true }

        // The backend user must exist before any data is sent. On failure keep
        // the properties and retry later — the gate itself retries creation on
        // the next demand.
        do {
            try await userManager.obtainUser()
        } catch {
            logger.warning("Failed to obtain user before sending properties: " + error.message)
            retrySendingProperties()
            return false
        }

        // Read here, after the user gate: obtaining the user may itself resolve
        // an identity and move the uid, and this batch belongs to whoever the
        // SDK is on once it has.
        return await postBatch(properties, userId: userIdProvider.getUserId(), schedulingRetries: true)
    }

    /// Posts one batch under an explicitly named uid. The uid is a parameter,
    /// not a read of the provider, because the user-switch flush may outlive
    /// the switch: it has to post under the user that queued the batch, not
    /// under whoever the provider holds by the time the request is built. Only
    /// the scheduled path may follow up with retries — the user-switch path
    /// cannot wait for them.
    private func postBatch(_ properties: [Qonversion.UserProperty], userId: String, schedulingRetries: Bool) async -> Bool {
        let items: RequestBodyArray = properties.map { ["key": $0.key, "value": $0.value] as RequestBodyDict }
        let body: RequestBodyDict = ["properties": items]
        let request = Request.sendProperties(userId: userId, body: body)
        do {
            let result: SendUserPropertiesResult? = try await requestProcessor.process(request: request, responseType: SendUserPropertiesResult.self)
            result?.propertyErrors.forEach({ propertyError in
                logger.error("Failed to save property " + propertyError.key + ": " + propertyError.error)
            })
            
            resetRetryState()

            propertiesStorage.clear(properties: properties)

            // Properties set while the batch was in flight.
            if schedulingRetries && !propertiesStorage.all().isEmpty {
                scheduleSendingProperties(withDelay: Constants.sendPropertiesMinDelaySec.rawValue)
            }

            return true
        } catch {
            if schedulingRetries {
                retrySendingProperties()
            }
            return false
        }
    }

    func clearDelayedProperties() {
        stateLock.lock()
        // Nothing pending is owed to anybody any more: stop the delay timer and
        // the round trip that would post the dropped batch.
        sendingTask?.cancel()
        sendingTask = nil
        sendingInFlight?.cancel()
        sendPropertiesRetryCount = 0
        sendPropertiesRetryDelay = Constants.sendPropertiesMinDelaySec.rawValue
        stateLock.unlock()

        propertiesStorage.clear()
    }

}

// MARK: - UserChangedObserver

extension UserPropertiesManager: UserChangedObserver {

    /// The pending batch belongs to the uid that queued it. The legacy SDK
    /// posted it after the switch, taking whatever uid was current by then and
    /// attributing the batch to the wrong user.
    ///
    /// A synchronous handoff, not a flush: the outgoing uid and the pending
    /// batch are snapshotted and the storage is emptied before this returns,
    /// and the network round trip is left to a background task. The switch —
    /// and therefore identify() at launch and logout() behind a sign-out
    /// button — waits for no I/O at all.
    func userWillChange() async {
        // Both snapshots are taken before the method returns, which is before
        // the caller can move the uid. Nothing read after this point can be the
        // new user's.
        let outgoingUserId: String = userIdProvider.getUserId()
        let outgoingBatch: [Qonversion.UserProperty] = propertiesStorage.all()
        guard !outgoingBatch.isEmpty else { return }

        // Handed over: the batch belongs to the task below and to nobody else.
        // The new user starts clean, and the scheduled sender — which reads the
        // storage, never this snapshot — cannot post it a second time.
        propertiesStorage.clear(properties: outgoingBatch)

        // Fire and forget, and deliberately retaining self: the batch has been
        // taken out of the storage, so this task is the only thing that can
        // still deliver it.
        Task {
            // A round trip already in flight carries part of the same batch;
            // waiting for it keeps the two posts from interleaving. Should it
            // succeed, the overlap is re-sent — the same keys with the same
            // values under the same uid, which the backend applies idempotently.
            if let inFlight: Task<Bool, Never> = self.currentSendingTask() {
                _ = await inFlight.value
            }

            // The whole misattribution guarantee, in one sentence: this post
            // holds its own uid and its own properties, both captured before
            // the switch, so it cannot read the new user's uid or the new
            // user's batch no matter how late it runs. No deadline, no
            // cancellation and no ordering assumption is needed to get that —
            // which is why there is none.
            //
            // Deliberately without the user gate: the user being switched away
            // from provably exists on the backend — both call sites (identify
            // and logout) are reached only after the creation pipeline has run
            // — so the call would buy nothing. It is not a deadlock hazard
            // either: UserManager is an actor and a reentrant call would simply
            // suspend. It is skipped because it is pointless.
            //
            // One attempt: a retry ladder would outlive its own relevance, and
            // dropping the batch on failure is the pre-existing policy.
            _ = await self.postBatch(outgoingBatch, userId: outgoingUserId, schedulingRetries: false)
        }
    }

    /// Anything queued after the handoff and before the switch completed is
    /// dropped: it may not be posted under the uid the SDK just switched to.
    func userDidChange() {
        clearDelayedProperties()
    }
}

// MARK: - Private

extension UserPropertiesManager {

    func processRequest(with token: String, requestedAt: TimeInterval = Date().timeIntervalSince1970) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sendAppleSearchAdsToken(token, requestedAt: requestedAt)
                self.logger.info(LoggerInfoMessages.appleSearchAdsAttributionRequestSucceeded.rawValue)
            } catch {
                self.logger.error("\(LoggerInfoMessages.appleSearchAdsAttributionRequestFailed.rawValue) \(error)")
            }
        }
    }

    /// The attribution endpoint acknowledges with an empty body, like every
    /// other data-sending flow — and, like them, needs the backend user first.
    /// `requested_at` is the moment the token was obtained, which the backend
    /// needs to match the attribution window.
    func sendAppleSearchAdsToken(_ token: String, requestedAt: TimeInterval = Date().timeIntervalSince1970) async throws {
        try await userManager.obtainUser()

        let body: RequestBodyDict = [
            "token": token,
            "requested_at": Int(requestedAt),
            "provider": StringConstants.appleAdServicesProvider.rawValue
        ]
        let request = Request.appleSearchAds(userId: userIdProvider.getUserId(), body: body)
        let _: EmptyApiResponse = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
    }
    
    private func scheduleSendingProperties(withDelay delaySec: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        // Cancel for the case, when the previous task was scheduled via "setProperty" call, but then retry for another request occurred.
        sendingTask?.cancel()

        sendingTask = Task<Void, Error>.delayed(byTimeInterval: TimeInterval(delaySec)) {
            self.clearScheduledTask()
            do {
                try await self.sendProperties()
            } catch {
                // sendProperties handles its own retries; anything reaching
                // here is unexpected and must not crash the schedule chain.
                self.logger.error("Failed to send user properties: \(error)")
            }
        }
    }

    private func clearScheduledTask() {
        stateLock.lock()
        defer { stateLock.unlock() }
        sendingTask = nil
    }

    /// Starts a batch round trip when none is in flight and cancels the
    /// pending schedule; nil means another one is already running.
    private func startSendingIfIdle() -> Task<Bool, Never>? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard sendingInFlight == nil else { return nil }

        sendingTask?.cancel()
        sendingTask = nil

        let task = Task<Bool, Never> { [weak self] () -> Bool in
            guard let self else { return false }
            // Cleared before the value reaches the awaiters, so a forced send
            // resuming right after can start the next round.
            defer { self.clearSendingInFlight() }

            return await self.performSend()
        }
        sendingInFlight = task

        return task
    }

    private func currentSendingTask() -> Task<Bool, Never>? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sendingInFlight
    }

    private func clearSendingInFlight() {
        stateLock.lock()
        defer { stateLock.unlock() }
        sendingInFlight = nil
    }

    private func resetRetryState() {
        stateLock.lock()
        defer { stateLock.unlock() }
        sendPropertiesRetryCount = 0
        sendPropertiesRetryDelay = Constants.sendPropertiesMinDelaySec.rawValue
    }

    private func retrySendingProperties() {
        stateLock.lock()
        sendPropertiesRetryCount += 1
        guard sendPropertiesRetryCount <= Constants.sendPropertiesMaxRetries.rawValue else {
            sendPropertiesRetryCount = 0
            sendPropertiesRetryDelay = Constants.sendPropertiesMinDelaySec.rawValue
            stateLock.unlock()
            logger.error("Giving up sending user properties after \(Constants.sendPropertiesMaxRetries.rawValue) attempts; kept for the next trigger.")
            return
        }
        sendPropertiesRetryDelay = delayCalculator.countDelay(minDelay: Constants.sendPropertiesMinDelaySec.rawValue, retriesCount: sendPropertiesRetryCount)
        let delay: Int = sendPropertiesRetryDelay
        stateLock.unlock()
        scheduleSendingProperties(withDelay: delay)
    }
}
