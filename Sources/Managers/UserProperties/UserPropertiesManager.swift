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
    // A forced send drains what was pending when it was called; the cap is what
    // bounds it when the storage keeps handing the same property back.
    case forceSendMaxRounds = 3
    // The production limits, in bytes: a property over them is refused by the
    // backend, and a refused batch takes every property in it down with it.
    case maxPropertyKeyBytes = 80
    case maxPropertyValueBytes = 120
    // Mirrors the gateway's v4MaxPropertiesCount: a request carrying more is
    // refused as invalid_data, and a refusal is terminal.
    case maxPropertiesPerBatch = 100
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

    /// Reads the AdServices attribution token. Throwing means "not right now"
    /// — the caller retries; nil means this platform has no token to give.
    typealias AttributionTokenReader = @Sendable () throws -> String?

    /// When and how often the attribution token is read. ObjC parity: the read
    /// happens off the caller's thread, a moment after launch, and a transient
    /// AdServices failure costs a retry rather than the token.
    struct AppleSearchAdsSchedule: Sendable {
        let initialDelay: TimeInterval
        let retryDelay: TimeInterval
        let maxAttempts: Int

        static let production = AppleSearchAdsSchedule(initialDelay: 5, retryDelay: 5, maxAttempts: 3)
    }

    /// The characters the production value contract refuses.
    private static let forbiddenValueCharacters = CharacterSet(charactersIn: "\n\r\"'")

    private let attributionTokenReader: AttributionTokenReader
    private let appleSearchAdsSchedule: AppleSearchAdsSchedule

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
        backgroundNotificationName: Notification.Name = UserPropertiesManager.backgroundNotificationName,
        attributionTokenReader: @escaping AttributionTokenReader = UserPropertiesManager.adServicesAttributionToken,
        appleSearchAdsSchedule: AppleSearchAdsSchedule = .production
    ) {
        self.attributionTokenReader = attributionTokenReader
        self.appleSearchAdsSchedule = appleSearchAdsSchedule
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
    
    /// The AdServices token of this install, or nil where the framework is not
    /// available. It is a blocking call that goes to the network.
    @Sendable
    static func adServicesAttributionToken() throws -> String? {
        #if canImport(AdServices)
        guard #available(iOS 14.3, macOS 11.1, visionOS 1.0, *) else { return nil }

        return try AAAttribution.attributionToken()
        #else
        return nil
        #endif
    }

    func collectAppleSearchAdsAttribution() {
        let read: AttributionTokenReader = attributionTokenReader
        let schedule: AppleSearchAdsSchedule = appleSearchAdsSchedule

        // The SDK documents this call for didFinishLaunchingWithOptions, so it
        // returns at once: the AdServices read is blocking, goes to the
        // network, and would otherwise stall the launch on the caller's thread.
        Task { [weak self] in
            await self?.collectAppleSearchAdsToken(reading: read, on: schedule)
        }
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
        guard key.utf8.count <= Constants.maxPropertyKeyBytes.rawValue else {
            logger.warning("User property key \"" + key + "\" is longer than \(Constants.maxPropertyKeyBytes.rawValue) bytes — the property is ignored.")
            return
        }
        guard value.utf8.count <= Constants.maxPropertyValueBytes.rawValue else {
            logger.warning("The value of the user property \"" + key + "\" is longer than \(Constants.maxPropertyValueBytes.rawValue) bytes — the property is ignored.")
            return
        }
        guard value.rangeOfCharacter(from: Self.forbiddenValueCharacters) == nil else {
            logger.warning("The value of the user property \"" + key + "\" contains a line break or a quote — the property is ignored.")
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

        // Only the exact properties pending on entry are owned by this call:
        // a key alone is not enough, because a host rewriting its value on a
        // timer would then keep the loop alive forever.
        let ownedProperties: Set<Qonversion.UserProperty> = Set(propertiesStorage.all())
        var round: Int = 0
        while round < Constants.forceSendMaxRounds.rawValue {
            if let inFlight: Task<Bool, Never> = currentSendingTask() {
                _ = await inFlight.value
            }

            let remaining: [Qonversion.UserProperty] = propertiesStorage.all().filter { ownedProperties.contains($0) }
            guard !remaining.isEmpty else { return }
            guard let task: Task<Bool, Never> = startSendingIfIdle() else {
                // Another sender took the slot between the two calls. Yield so
                // this branch can never spin without suspending.
                await Task.yield()
                continue
            }

            round += 1
            let succeeded: Bool = await task.value
            guard succeeded else { return }
        }
    }

    /// Which sender a post belongs to. The scheduled sender still owns its
    /// batch in the storage and owns the retry ladder; the user-switch handoff
    /// owns neither — it took its copy out before the switch and everything
    /// left behind belongs to the incoming user.
    private enum BatchOwner {
        case scheduledSender
        case userSwitchHandoff
    }

    /// One batch round trip. Returns false when the batch did not reach the
    /// backend — the properties stay in the storage and a retry is scheduled.
    private func performSend() async -> Bool {
        let properties: [Qonversion.UserProperty] = propertiesStorage.all()
        let userId: String = userIdProvider.getUserId()

        guard !properties.isEmpty else { return true }

        // The backend user must exist before any data is sent.
        do {
            try await userManager.obtainUser()
        } catch {
            logger.warning("Failed to obtain user before sending properties: " + error.message)
            retrySendingProperties()
            return false
        }

        // The uid only moves through a switch, and a switch claims the pending
        // batch in userWillChange first: a moved uid means the batch is theirs.
        guard userIdProvider.getUserId() == userId else { return true }

        return await postBatch(properties, userId: userId, owner: .scheduledSender)
    }

    /// How one chunk's round trip settled.
    private enum ChunkOutcome {
        case delivered
        case rejected
        case retriable
    }

    /// The uid is a parameter, not a read of the provider: the user-switch
    /// flush may outlive the switch and must post under the queuing user.
    private func postBatch(_ properties: [Qonversion.UserProperty], userId: String, owner: BatchOwner) async -> Bool {
        let size: Int = Constants.maxPropertiesPerBatch.rawValue
        var delivered: Bool = true
        for start in stride(from: 0, to: properties.count, by: size) {
            let end: Int = min(start + size, properties.count)
            let chunk: [Qonversion.UserProperty] = Array(properties[start..<end])
            let outcome: ChunkOutcome = await postChunk(chunk, userId: userId, owner: owner)
            if outcome == .rejected {
                // The other chunks are valid on their own and still owed.
                delivered = false
                continue
            }
            // The remainder stays in the storage under the retry the chunk
            // scheduled — resetting the ladder here would undo it.
            if outcome == .retriable { return false }
        }

        guard owner == .scheduledSender else { return delivered }

        resetRetryState()

        // Properties set while the batch was in flight.
        if !propertiesStorage.all().isEmpty {
            scheduleSendingProperties(withDelay: Constants.sendPropertiesMinDelaySec.rawValue)
        }

        return delivered
    }

    private func postChunk(_ chunk: [Qonversion.UserProperty], userId: String, owner: BatchOwner) async -> ChunkOutcome {
        let items: RequestBodyArray = chunk.map { ["key": $0.key, "value": $0.value] as RequestBodyDict }
        let body: RequestBodyDict = ["properties": items]
        let request = Request.sendProperties(userId: userId, body: body)
        do {
            let result: SendUserPropertiesResult? = try await requestProcessor.process(request: request, responseType: SendUserPropertiesResult.self)
            result?.propertyErrors.forEach({ propertyError in
                logger.error("Failed to save property " + propertyError.key + ": " + propertyError.error)
            })

            guard owner == .scheduledSender else { return .delivered }

            propertiesStorage.clear(properties: chunk)

            return .delivered
        } catch {
            // A refused batch is refused again on every trigger, and it stays
            // in the storage: one value the backend will not take would block
            // every property set afterwards. Drop it instead, and name it.
            if error.isRejectedByBackend {
                logger.error("Qonversion rejected these user properties, they are dropped: " + chunk.map(\.key).joined(separator: ", "))
                // Same ownership rule as the success path: after a switch the
                // storage belongs to the incoming user, and the handoff batch
                // was taken out of it before the post.
                guard owner == .scheduledSender else { return .rejected }

                propertiesStorage.clear(properties: chunk)

                return .rejected
            }

            if owner == .scheduledSender {
                retrySendingProperties()
            }
            return .retriable
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
            _ = await self.postBatch(outgoingBatch, userId: outgoingUserId, owner: .userSwitchHandoff)
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

    /// Waits out the schedule's delay, then reads the token, retrying a
    /// transient AdServices failure up to the attempt budget. ObjC parity:
    /// the token is not available the instant the app launches.
    func collectAppleSearchAdsToken(reading read: @escaping AttributionTokenReader, on schedule: AppleSearchAdsSchedule) async {
        var delay: TimeInterval = schedule.initialDelay
        for _ in 0..<max(schedule.maxAttempts, 1) {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }

            let requestedAt: TimeInterval = Date().timeIntervalSince1970
            do {
                guard let token: String = try await readAttributionToken(read), !token.isEmpty else {
                    return logger.warning(LoggerInfoMessages.unableToCollectAppleSearchAdsAttribution.rawValue)
                }

                return processRequest(with: token, requestedAt: requestedAt)
            } catch {
                logger.error("\(LoggerInfoMessages.failedToCollectAppleSearchAdsAttribution.rawValue) \(error)")
                delay = schedule.retryDelay
            }
        }
    }

    /// The read blocks for as long as the AdServices request takes, so it runs
    /// on a background queue instead of a cooperative pool thread.
    private func readAttributionToken(_ read: @escaping AttributionTokenReader) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try read())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

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
        let body: RequestBodyDict = [
            "token": token,
            "requested_at": Int(requestedAt),
            "provider": StringConstants.appleAdServicesProvider.rawValue
        ]

        do {
            try await userManager.obtainUser()
        } catch {
            // The request is sent anyway. An offline launch is exactly the
            // attribution window ASA exists for, the token is minted once per
            // install and is never re-readable, and the only durable place it
            // can wait is the offline replay queue — which RequestProcessor
            // fills from requests it could not deliver.
            logger.warning("Failed to obtain user before sending the Apple Search Ads token: " + error.message)
        }

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
