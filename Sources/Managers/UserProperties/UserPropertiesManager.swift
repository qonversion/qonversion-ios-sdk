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

    /// Which app host the SDK is compiled into.
    enum BackgroundFlushHost {
        /// The watch app runs as an app extension: there is no UIApplication.
        case watchExtension
        /// iOS, tvOS, visionOS and Mac Catalyst.
        case uiKitApplication
        /// A Mac app never enters the background.
        case appKitApplication
        /// Anything else: nothing posts it, the batch waits for its delay timer.
        case none
    }

    /// Raw strings on purpose: the typed constants only exist on the platform
    /// that declares them, and every mapping has to exist in every build.
    static func backgroundFlushNotificationName(for host: BackgroundFlushHost) -> Notification.Name {
        switch host {
        case .watchExtension:
            return Notification.Name("NSExtensionHostDidEnterBackgroundNotification")
        case .uiKitApplication:
            return Notification.Name("UIApplicationDidEnterBackgroundNotification")
        case .appKitApplication:
            // Legacy ObjC parity: a Mac app has no background transition to hook.
            return Notification.Name("NSApplicationDidResignActiveNotification")
        case .none:
            return Notification.Name("qonversion.notifications.appDidEnterBackground")
        }
    }

    static var currentBackgroundFlushHost: BackgroundFlushHost {
        // watchOS imports UIKit but has no UIApplication: match it first.
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

        // Only the batch pending on entry is owned by this call: chasing
        // properties set while it runs could loop forever.
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

        // The backend user must exist before any data is sent.
        do {
            try await userManager.obtainUser()
        } catch {
            logger.warning("Failed to obtain user before sending properties: " + error.message)
            retrySendingProperties()
            return false
        }

        // Read after obtaining the user: that may itself resolve an identity
        // and move the uid.
        return await postBatch(properties, userId: userIdProvider.getUserId(), schedulingRetries: true)
    }

    /// The uid is a parameter, not a read of the provider: the user-switch
    /// flush may outlive the switch and must post under the queuing user.
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

    /// Synchronous handoff, not a flush: the snapshot below owns its uid and
    /// its batch, so a post arriving arbitrarily late cannot misattribute them.
    func userWillChange() async {
        let outgoingUserId: String = userIdProvider.getUserId()
        let outgoingBatch: [Qonversion.UserProperty] = propertiesStorage.all()
        guard !outgoingBatch.isEmpty else { return }

        // The new user starts clean; the scheduled sender reads the storage,
        // never this snapshot, so it cannot post the batch a second time.
        propertiesStorage.clear(properties: outgoingBatch)

        // Retains self on purpose: this task is the only thing left that can
        // deliver the batch.
        Task {
            // Trade-off: waiting keeps the posts from interleaving, at the cost
            // of re-sending the overlap — idempotent, same keys and same uid.
            if let inFlight: Task<Bool, Never> = self.currentSendingTask() {
                _ = await inFlight.value
            }

            // No user gate on purpose: both call sites run after user creation.
            // One attempt on purpose: a retry ladder would outlive its relevance.
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

    /// `requested_at` must be the moment the token was obtained: the backend
    /// matches it against the attribution window.
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

        // A retry supersedes a schedule left over from setProperty.
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
