//
//  Qonversion.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation
import StoreKit

/// A stream that stays open until its source exists, then forwards it whole.
///
/// A host that starts iterating before ``Qonversion/Qonversion/initialize(with:)``
/// would otherwise be handed an already finished stream: its `for await` exits
/// immediately and never runs again, so everything the SDK later produces is
/// lost with no way for the host to notice. Internal so the behavior is
/// asserted without initializing the process-wide singleton.
func awaitingStream<Element: Sendable>(_ source: @escaping @Sendable () async -> AsyncStream<Element>) -> AsyncStream<Element> {
    return AsyncStream { continuation in
        let task: Task<Void, Never> = Task {
            for await element in await source() {
                continuation.yield(element)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

/// An entry point to use Qonversion SDK.
// @unchecked: the manager graph is the only mutable state and every read and
// write of it goes through stateLock.
public final class Qonversion: @unchecked Sendable {
    
    // MARK: - Public
    
    /// Use this variable to get the current initialized instance of the Qonversion SDK.
    /// Please, use the variable only after initializing the SDK.
    /// - Returns: the current initialized instance of the ``Qonversion/Qonversion`` SDK
    public static let shared = Qonversion()
    
    /// An entry point to use Qonversion SDK. Call to initialize Qonversion SDK with required and extra configs.
    /// The function is the best way to set additional configs you need to use Qonversion SDK.
    /// - Parameter configuration: a config that contains key SDK settings.
    /// - Returns: Initialized instance of the ``Qonversion`` SDK.
    @discardableResult
    public static func initialize(with configuration: Configuration) -> Qonversion {
        // Re-initializing would rebuild the manager graph under the feet of
        // the background tasks the first call spawned. The same lock guards
        // every read of the graph — no suspension point is crossed while it
        // is held (the tasks below are spawned, never awaited).
        shared.stateLock.lock()
        guard shared.managers == nil else {
            let logger: LoggerWrapper? = shared.logger
            shared.stateLock.unlock()
            logger?.warning("Qonversion.initialize called more than once — the repeated call is ignored.")
            return shared
        }

        let assembly: QonversionAssembly = QonversionAssembly(apiKey: configuration.apiKey, userDefaults: configuration.userDefaults, launchMode: configuration.launchMode, baseURL: configuration.baseURL, entitlementsCacheLifetime: configuration.entitlementsCacheLifetime, logLevel: configuration.logLevel)
        // Deterministic teardown order for a user switch, independent of the
        // order the managers happen to be built in.
        assembly.registerUserChangeObservers()
        // Replay requests that failed on transport in previous sessions.
        assembly.replayStoredRequests()
        let managers = Managers(
            assembly: assembly,
            userManager: assembly.userManager(),
            purchasesManager: assembly.purchasesManager(),
            entitlementsManager: assembly.entitlementsManager(),
            userPropertiesManager: assembly.userPropertiesManager(),
            deviceManager: assembly.deviceManager(),
            productsManager: assembly.productsManager(),
            remoteConfigManager: assembly.remoteConfigManager()
        )
        shared.logger = assembly.servicesAssembly.miscAssemblyLogger()
        shared.managers = managers
        // Streams handed out before this point are waiting for the graph; they
        // start delivering from here on. Resumed outside the lock.
        let waiters: [CheckedContinuation<Managers, Never>] = shared.managersWaiters
        shared.managersWaiters = []
        shared.stateLock.unlock()
        waiters.forEach { $0.resume(returning: managers) }

        // Capture uncaught exceptions raised inside the SDK from here on, and
        // ship whatever the previous launch left behind. Chained: the host's
        // own crash reporter keeps working.
        assembly.startCrashReporting()
        Task {
            await assembly.sendStoredCrashReports()
        }

        // Start consuming out-of-band transaction updates (renewals, refunds,
        // Ask to Buy approvals, purchases on other devices).
        managers.purchasesManager.startObservingTransactions()

        // Re-report transactions left unfinished by previous sessions
        // (reported in both modes; finished only in subscription management).
        Task {
            await managers.purchasesManager.processUnfinishedTransactions()
        }

        // Prices and offers are per-storefront; a change must invalidate the
        // enriched catalog.
        managers.productsManager.startObservingStorefrontChanges()

        // The product → permissions mapping powers the offline entitlements
        // calculation, which answers in BOTH launch modes — Analytics reaches
        // it through every deferred purchase. Refreshed on every launch, and
        // reloaded on demand should this one fail.
        Task {
            await managers.productsManager.loadProductPermissions()
        }

        // Attribution ids of integrated SDKs (Adjust, AppsFlyer, Facebook)
        // become available after those SDKs initialize — collect with the
        // same delay production uses.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            managers.userPropertiesManager.collectIntegrationsData()
        }

        // Warm up the user gate first, then create/refresh the backend
        // device record — the device row belongs to a user the backend has
        // seen. Failures are fine: the gate retries on the next demand.
        Task {
            _ = try? await managers.userManager.obtainUser()
            await managers.deviceManager.collectDeviceInfo()
        }

        return Qonversion.shared
    }
    
    /// Links the current Qonversion user to your unique user id and shares purchase data.
    /// If the given id is already linked to another Qonversion user, the SDK switches to that user.
    /// - Parameter userId: your unique user id.
    /// - Returns: the current ``Qonversion/Qonversion/User``.
    @discardableResult
    public func identify(_ userId: String) async throws -> Qonversion.User {
        let managers: Managers = try requireManagers()

        return try await managers.userManager.identify(userId)
    }

    /// Unlinks the current user from your unique user id and resets to a
    /// fresh anonymous user. Await the call before the next identify — the
    /// reset is guaranteed to be finished when it returns.
    public func logout() async {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.logout called before Qonversion.initialize — there is no user to reset yet.")
            return
        }

        await managers.userManager.logout()
    }

    /// Returns information about the current Qonversion user.
    public func userInfo() async throws -> Qonversion.User {
        let managers: Managers = try requireManagers()

        return try await managers.userManager.userInfo()
    }

    /// Returns Qonversion products in association with App Store products.
    /// - Throws: Possible error during the products request or Qonversion initialization error.
    public func products() async throws -> [Qonversion.Product] {
        let managers: Managers = try requireManagers()

        return try await managers.productsManager.products()
    }

    /// Resolves the user's eligibility for the introductory offers of the
    /// given Qonversion products. The check runs on the device via StoreKit 2.
    /// - Parameter productIds: Qonversion product identifiers.
    public func checkTrialIntroEligibility(_ productIds: [String]) async throws -> [String: Qonversion.IntroEligibilityStatus] {
        let managers: Managers = try requireManagers()

        return try await managers.productsManager.checkTrialIntroEligibility(productIds: productIds)
    }

    /// Buys the product through the App Store and validates the purchase with
    /// the Qonversion backend. The transaction is finished only after the
    /// backend confirms the purchase. When the backend is unreachable, the
    /// purchase still succeeds with locally calculated entitlements.
    /// - Parameter product: the product to purchase.
    /// - Returns: ``Qonversion/Qonversion/PurchaseResult`` with the verified
    ///   transaction and the user's entitlements.
    @discardableResult
    public func purchase(_ product: Qonversion.Product, options: Qonversion.PurchaseOptions? = nil) async throws -> Qonversion.PurchaseResult {
        let managers: Managers = try requireManagers()

        return try await managers.purchasesManager.purchase(product, options: options)
    }

    /// Reports purchases made by your own StoreKit 2 code so Qonversion can
    /// track them (Analytics mode). Pass the verification results you receive
    /// from `Product.PurchaseResult` or `Transaction.updates`. The SDK never
    /// finishes these transactions — your app owns their lifecycle.
    /// - Returns: true when every purchase was reported to Qonversion;
    ///   failed reports are retried automatically by the offline queue.
    @discardableResult
    public func handlePurchases(_ verificationResults: [VerificationResult<StoreKit.Transaction>]) async -> Bool {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.handlePurchases called before Qonversion.initialize — \(verificationResults.count) purchase(s) were NOT reported. Initialize the SDK first, then hand them over.")
            return false
        }

        return await managers.purchasesManager.handle(purchasedTransactions: verificationResults)
    }

    /// Requests a signed promotional offer for the product's subscription
    /// discount. Pass the result to ``purchase(_:options:)`` via
    /// ``PurchaseOptions/promoOffer``.
    public func getPromotionalOffer(for product: Qonversion.Product, discountId: String) async throws -> Qonversion.PromotionalOffer {
        let managers: Managers = try requireManagers()

        return try await managers.purchasesManager.promotionalOffer(for: product, discountId: discountId)
    }

    /// A stream of purchases promoted in the App Store. Call purchase() on a
    /// received intent to proceed — right away or whenever the app is ready;
    /// dropping the intent defers the purchase. An intent arriving before the
    /// first subscription is buffered and handed to it exactly once, never
    /// repeated to a stream created later:
    ///
    ///     for await intent in Qonversion.shared.promoPurchaseIntents {
    ///         try await intent.purchase()
    ///     }
    public var promoPurchaseIntents: AsyncStream<PromoPurchaseIntent> {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.promoPurchaseIntents was read before Qonversion.initialize — the stream starts delivering once the SDK is initialized.")

            return pendingStream { $0.purchasesManager.promoPurchaseIntents() }
        }

        return managers.purchasesManager.promoPurchaseIntents()
    }

    /// A stream of purchases that completed outside of ``purchase(_:options:)``:
    /// Ask to Buy and SCA approvals, renewals, refunds and purchases made on
    /// other devices. Delivered in both launch modes; when the backend was
    /// unreachable the entitlements are calculated locally and
    /// ``Qonversion/Qonversion/DeferredPurchase/entitlementsSource`` says so.
    /// Like StoreKit's `Transaction.updates`, every access returns an
    /// independent stream. Each purchase is delivered exactly once, so it is
    /// safe to grant content straight from the loop:
    ///
    /// * a purchase produced while one or more streams are being iterated
    ///   reaches all of them at that moment;
    /// * a purchase produced while nobody is listening waits — with no
    ///   deadline — for the next stream and is handed to that one alone;
    /// * a purchase that has already reached a stream is never repeated to a
    ///   stream created later, so a screen that re-appears and subscribes
    ///   again does not grant the content twice;
    /// * a purchase nobody received before the app was terminated comes back
    ///   on a later launch, as long as its transaction is still unfinished.
    ///
    /// A stream you create and drop without iterating counts as having
    /// received what was waiting, so build the stream where you consume it —
    /// and prefer one long-lived subscription for granting content:
    ///
    ///     for await purchase in Qonversion.shared.deferredPurchases {
    ///         grantAccess(with: purchase.entitlements, for: purchase.transaction)
    ///     }
    public var deferredPurchases: AsyncStream<Qonversion.DeferredPurchase> {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.deferredPurchases was read before Qonversion.initialize — the stream starts delivering once the SDK is initialized.")

            return pendingStream { $0.purchasesManager.deferredPurchases() }
        }

        return managers.purchasesManager.deferredPurchases()
    }

    /// The entitlements-only projection of ``deferredPurchases``, for hosts
    /// that only refresh their access state. It also carries the changes no
    /// purchase describes — a refund or a family-sharing revocation — so it is
    /// the one stream to follow to keep access in sync. Each value is the
    /// complete access state, not a delta, and stays readable by a stream
    /// created later:
    ///
    ///     for await entitlements in Qonversion.shared.entitlementsUpdates { ... }
    public var entitlementsUpdates: AsyncStream<[String: Qonversion.Entitlement]> {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.entitlementsUpdates was read before Qonversion.initialize — the stream starts delivering once the SDK is initialized.")

            return pendingStream { $0.purchasesManager.entitlementsUpdates() }
        }

        return managers.purchasesManager.entitlementsUpdates()
    }

    #if os(iOS) || os(visionOS)
    /// Presents the system sheet for redeeming App Store offer codes.
    public func presentCodeRedemptionSheet() {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.presentCodeRedemptionSheet called before Qonversion.initialize — no sheet was presented. Call it after initializing the SDK.")
            return
        }

        managers.purchasesManager.presentCodeRedemptionSheet()
    }

    /// Presents the App Store offer code redemption sheet in the given scene.
    @available(iOS 16.0, *)
    public func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        let managers: Managers = try requireManagers()

        try await managers.purchasesManager.presentOfferCodeRedeemSheet(in: scene)
    }
    #endif

    #if os(visionOS)
    /// Names the scene the App Store purchase sheet is confirmed in.
    ///
    /// visionOS has no scene-less purchase call — StoreKit needs to know which
    /// of the app's scenes the sheet belongs to, and only the app can answer
    /// that. Call it after ``initialize(with:)`` and before the first
    /// ``purchase(_:options:)``, and update it whenever the scene the paywall
    /// lives in changes:
    ///
    ///     Qonversion.initialize(with: configuration)
    ///     Qonversion.shared.setPurchaseConfirmationScene(windowScene)
    ///
    /// The scene is held weakly, so a discarded scene is not kept alive.
    /// Purchasing without one throws a ``QonversionError`` of type
    /// ``QonversionErrorType/purchaseSceneMissing``.
    ///
    /// Every other platform ignores the concept: this method does not exist
    /// there, and ``purchase(_:options:)`` needs no scene.
    @MainActor
    public func setPurchaseConfirmationScene(_ scene: UIScene?) {
        guard let managers: Managers = currentManagers() else {
            // Dropping the scene silently would surface much later as a
            // .purchaseSceneMissing on the first purchase, with nothing
            // pointing back at the ordering mistake that caused it.
            currentLogger().warning("Qonversion.setPurchaseConfirmationScene called before Qonversion.initialize — the scene is ignored. Call it after initializing the SDK, otherwise purchases fail with .purchaseSceneMissing.")
            return
        }

        managers.purchasesManager.setPurchaseConfirmationScene(scene)
    }
    #endif

    /// Sends the historical App Store transactions to Qonversion once per
    /// install. Call it right after the first launch of the app version that
    /// integrates the SDK, so the existing subscribers' data reaches the
    /// analytics.
    public func syncHistoricalData() {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.syncHistoricalData called before Qonversion.initialize — nothing was synced. Call it after initializing the SDK.")
            return
        }

        Task {
            await managers.purchasesManager.syncHistoricalData()
        }
    }

    /// Restores the user's purchases and returns the entitlements.
    /// When the backend is unreachable, entitlements are calculated locally.
    @discardableResult
    public func restore() async throws -> [String: Qonversion.Entitlement] {
        let managers: Managers = try requireManagers()

        return try await managers.purchasesManager.restore()
    }

    /// Returns the user's entitlements keyed by entitlement id.
    /// When the backend is unreachable (5xx / connection issues), entitlements
    /// are calculated locally from StoreKit data and the cached mapping.
    public func checkEntitlements() async throws -> [String: Qonversion.Entitlement] {
        let managers: Managers = try requireManagers()

        return try await managers.entitlementsManager.entitlements()
    }

    /// Sends all the properties set since the last batch right away, without
    /// waiting for the batching delay. Delivery failures are retried by the
    /// SDK automatically.
    public func forceSendProperties() async {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.forceSendProperties called before Qonversion.initialize — there are no properties to send yet.")
            return
        }

        try? await managers.userPropertiesManager.sendProperties(force: true)
    }

    /// Whether the bundled fallback file (`qonversion_ios_fallbacks.json`) is
    /// present in the app bundle and parses. Use in debug builds to verify the
    /// offline fallback setup.
    public func isFallbackFileAccessible() -> Bool {
        guard let managers: Managers = currentManagers() else {
            // false here means "cannot tell", not "no such file" — the two are
            // indistinguishable to the caller without this line.
            currentLogger().warning("Qonversion.isFallbackFileAccessible called before Qonversion.initialize — the bundled file was not checked at all.")
            return false
        }

        return managers.productsManager.isFallbackFileAccessible()
    }

    /// Collects Apple Search Ads Attribution data
    /// Available only for iOS 14.3+
    /// See details in the [Apple official documentation](https://developer.apple.com/documentation/iad/setting-up-apple-search-ads-attribution)
    public func collectAppleSearchAdsAttribution() {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.collectAppleSearchAdsAttribution called before Qonversion.initialize — the attribution was not collected. Call it after initializing the SDK.")
            return
        }

        managers.userPropertiesManager.collectAppleSearchAdsAttribution()
    }
    
    /// Collects advertising ID
    /// On iOS 14.5+, after requesting the app tracking permission using ATT, you need to notify Qonversion if tracking is allowed and IDFA is available.
    public func collectAdvertisingId() {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.collectAdvertisingId called before Qonversion.initialize — the advertising id was not collected. Call it after initializing the SDK.")
            return
        }

        managers.deviceManager.collectAdvertisingId()
    }
    
    /// Sets Qonversion defined user properties, like email or appsFlyer user ID.
    /// - Note that using ``Qonversion/Qonversion/UserPropertyKey/custom`` here will do nothing.
    /// - To set custom user property, use ``Qonversion/Qonversion/setCustomUserProperty(key:value:)``  instead.
    /// - Parameters:
    ///   - key: Defined enum key
    ///   - value: Property value
    public func setUserProperty(key: UserPropertyKey, value: String) {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.setUserProperty called before Qonversion.initialize — the property was dropped. Call it after initializing the SDK.")
            return
        }

        managers.userPropertiesManager.setUserProperty(key: key, value: value)
    }
    
    /// Sets custom user property
    /// - Parameters:
    ///   - key: Custom property key
    ///   - value: Property value
    public func setCustomUserProperty(key: String, value: String) {
        guard let managers: Managers = currentManagers() else {
            currentLogger().warning("Qonversion.setCustomUserProperty called before Qonversion.initialize — the property was dropped. Call it after initializing the SDK.")
            return
        }

        managers.userPropertiesManager.setCustomUserProperty(key: key, value: value)
    }
    
    /// This method returns all the properties, set for the current Qonversion user.
    /// All set properties are sent to the server with delay, so if you call
    /// this function right after setting some property, it may not be included in the result.
    /// - Returns: ``Qonversion/Qonversion/UserProperties`` that contains all the properties, set for the current Qonversion user.
    /// - Throws: Possible error during the properties request or Qonversion initialization error if the method is called before initialization.
    public func userProperties() async throws -> UserProperties {
        let managers: Managers = try requireManagers()

        return try await managers.userPropertiesManager.userProperties()
    }
    
    /// Returns Qonversion default remote config object or one defined by the context key.
    /// Use this function to get the remote config with specific payload and experiment info.
    /// - Parameters:
    ///   - contextKey: Context key to get remote config for
    /// - Returns: ``Qonversion/Qonversion/RemoteConfig`` for the specified context key or default one if no key provided.
    /// - Throws: Possible error during the remote config request or Qonversion initialization error if the method is called before initialization.
    public func remoteConfig(contextKey: String? = nil) async throws -> Qonversion.RemoteConfig {
        let managers: Managers = try requireManagers()

        return try await managers.remoteConfigManager.loadRemoteConfig(contextKey: contextKey)
    }
    
    /// Returns Qonversion remote config objects for all existing context key (including empty one).
    /// Use this function to get the remote configs with specific payload and experiment info.
    /// - Returns: ``Qonversion/Qonversion/RemoteConfigList`` with all the remote configs for the current user.
    /// - Throws: Possible error during the remote config request or Qonversion initialization error if the method is called before initialization.
    public func remoteConfigList() async throws -> Qonversion.RemoteConfigList {
        let managers: Managers = try requireManagers()

        return try await managers.remoteConfigManager.loadRemoteConfigList()
    }

    /// Returns Qonversion remote config objects by a list of context keys.
    /// Use this function to get the remote configs with specific payload and experiment info.
    /// - Parameters:
    ///   - contextKeys:list of context keys to get remote configs for.
    ///   - includeEmptyContextKey: set to true if you want to include remote config with empty context key to the result.
    /// - Returns: ``Qonversion/Qonversion/RemoteConfigList`` with the requested remote configs for the current user.
    /// - Throws: Possible error during the remote config list request or Qonversion initialization error if the method is called before initialization.
    public func remoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        let managers: Managers = try requireManagers()

        return try await managers.remoteConfigManager.loadRemoteConfigList(contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to attach the user to the remote configuration.
    /// - Parameters:
    ///   - id: identifier of the remote configuration.
    /// - Throws: Possible error during the attaching process or Qonversion initialization error if the method is called before initialization.
    public func attachUserToRemoteConfiguration(id: String) async throws {
        let managers: Managers = try requireManagers()

        try await managers.remoteConfigManager.attachUserToRemoteConfig(id: id)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to detach the user from the remote configuration.
    /// - Parameters:
    ///   - id: identifier of the remote configuration.
    /// - Throws: Possible error during the detaching process or Qonversion initialization error if the method is called before initialization.
    public func detachUserFromRemoteConfiguration(id: String) async throws {
        let managers: Managers = try requireManagers()

        try await managers.remoteConfigManager.detachUserFromRemoteConfig(id: id)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to attach the user to the experiment.
    /// - Parameters:
    ///   - id: identifier of the experiment
    ///   - groupId: identifier of the experiment group
    /// - Throws: Possible error during the attaching process or Qonversion initialization error if the method is called before initialization.
    public func attachUserToExperiment(id: String, groupId: String) async throws {
        let managers: Managers = try requireManagers()

        try await managers.remoteConfigManager.attachUserToExperiment(id: id, groupId: groupId)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to detach the user to the experiment.
    /// - Parameters:
    ///   - id: identifier of the experiment
    /// - Throws: Possible error during the detaching process or Qonversion initialization error if the method is called before initialization.
    public func detachUserFromExperiment(id: String) async throws {
        let managers: Managers = try requireManagers()

        try await managers.remoteConfigManager.detachUserFromExperiment(id: id)
    }

    // MARK: - Private

    /// The whole manager graph, written once by initialize() and read as one
    /// value: a public call either sees the complete graph or none of it.
    /// The facade owns the assembly: managers hold their dependencies, but
    /// cross-cutting pieces (user-change observers, the weak assembly
    /// back-references) live only as long as the assemblies do.
    // @unchecked: every manager is thread-safe on its own — an actor or a
    // lock-guarded @unchecked Sendable type.
    private struct Managers: @unchecked Sendable {
        let assembly: QonversionAssembly
        let userManager: UserManagerInterface
        let purchasesManager: PurchasesManagerInterface
        let entitlementsManager: EntitlementsManagerInterface
        let userPropertiesManager: UserPropertiesManagerInterface
        let deviceManager: DeviceManagerInterface
        let productsManager: ProductsManagerInterface
        let remoteConfigManager: RemoteConfigManagerInterface
    }

    private let stateLock = NSLock()
    private var managers: Managers?
    private var logger: LoggerWrapper?

    /// Streams created before initialize(), waiting for the graph to exist.
    private var managersWaiters: [CheckedContinuation<Managers, Never>] = []

    /// Suspends until initialize() builds the graph. Never times out: a host
    /// that subscribes early and initializes later is a supported order, and a
    /// deadline would turn it back into the silent loss it exists to prevent.
    private func awaitManagers() async -> Managers {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Managers, Never>) in
            stateLock.lock()
            if let managers {
                stateLock.unlock()
                continuation.resume(returning: managers)
                return
            }
            managersWaiters.append(continuation)
            stateLock.unlock()
        }
    }

    /// The stream to hand a caller that arrived before initialize(): it starts
    /// delivering as soon as the SDK is initialized.
    private func pendingStream<Element: Sendable>(_ source: @escaping @Sendable (Managers) -> AsyncStream<Element>) -> AsyncStream<Element> {
        return awaitingStream { [weak self] in
            guard let self else { return AsyncStream { $0.finish() } }

            return source(await self.awaitManagers())
        }
    }

    /// A snapshot of the graph taken under the lock. The lock is released
    /// before the caller awaits anything.
    private func currentManagers() -> Managers? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return managers
    }

    /// The configured logger, or the SDK's default one when initialize() has
    /// not run yet: a warning about calling too early is worthless if it only
    /// prints once the call is no longer too early.
    private func currentLogger() -> LoggerWrapper {
        stateLock.lock()
        let configured: LoggerWrapper? = logger
        stateLock.unlock()

        return configured ?? LoggerWrapper.make(logLevel: .verbose)
    }

    private func requireManagers() throws -> Managers {
        guard let managers: Managers = currentManagers() else { throw QonversionError.initializationError() }

        return managers
    }

    private init() { }
}
