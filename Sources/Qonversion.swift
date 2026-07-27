//
//  Qonversion.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation
import StoreKit

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
            shared.stateLock.unlock()
            shared.logger?.warning("Qonversion.initialize called more than once — the repeated call is ignored.")
            return shared
        }

        let assembly: QonversionAssembly = QonversionAssembly(apiKey: configuration.apiKey, userDefaults: configuration.userDefaults, launchMode: configuration.launchMode, baseURL: configuration.baseURL, entitlementsCacheLifetime: configuration.entitlementsCacheLifetime, logLevel: configuration.logLevel, environment: configuration.environment)
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
        shared.stateLock.unlock()

        // Start consuming out-of-band transaction updates (renewals, refunds,
        // Ask to Buy approvals, purchases on other devices).
        managers.purchasesManager.startObservingTransactions()

        // Re-report transactions left unfinished by previous sessions
        // (reported in both modes; finished only in subscription management).
        Task {
            await managers.purchasesManager.processUnfinishedTransactions()
        }

        // In subscription-management mode the SDK needs the product →
        // permissions mapping for local entitlements calculation; refresh the
        // persistent cache on every launch.
        if configuration.launchMode == .subscriptionManagement {
            Task {
                await managers.productsManager.loadProductPermissions()
            }
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
        guard let managers: Managers = currentManagers() else { return }

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
        guard let managers: Managers = currentManagers() else { return false }

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
    /// dropping the intent defers the purchase. Intents arriving before the
    /// first subscription are buffered:
    ///
    ///     for await intent in Qonversion.shared.promoPurchaseIntents {
    ///         try await intent.purchase()
    ///     }
    public var promoPurchaseIntents: AsyncStream<PromoPurchaseIntent> {
        guard let managers: Managers = currentManagers() else { return AsyncStream { $0.finish() } }

        return managers.purchasesManager.promoPurchaseIntents()
    }

    /// A stream of purchases that completed outside of ``purchase(_:options:)``:
    /// Ask to Buy and SCA approvals, renewals, refunds and purchases made on
    /// other devices. Delivered in both launch modes; when the backend was
    /// unreachable the entitlements are calculated locally and
    /// ``Qonversion/Qonversion/DeferredPurchase/entitlementsSource`` says so.
    /// Like StoreKit's `Transaction.updates`, every access returns an
    /// independent stream, and purchases processed before the first
    /// subscription are buffered:
    ///
    ///     for await purchase in Qonversion.shared.deferredPurchases {
    ///         grantAccess(with: purchase.entitlements, for: purchase.transaction)
    ///     }
    public var deferredPurchases: AsyncStream<Qonversion.DeferredPurchase> {
        guard let managers: Managers = currentManagers() else { return AsyncStream { $0.finish() } }

        return managers.purchasesManager.deferredPurchases()
    }

    /// The entitlements-only projection of ``deferredPurchases``, for hosts
    /// that only refresh their access state:
    ///
    ///     for await entitlements in Qonversion.shared.entitlementsUpdates { ... }
    public var entitlementsUpdates: AsyncStream<[String: Qonversion.Entitlement]> {
        guard let managers: Managers = currentManagers() else { return AsyncStream { $0.finish() } }

        return managers.purchasesManager.entitlementsUpdates()
    }

    #if os(iOS) || os(visionOS)
    /// Presents the system sheet for redeeming App Store offer codes.
    public func presentCodeRedemptionSheet() {
        currentManagers()?.purchasesManager.presentCodeRedemptionSheet()
    }

    /// Presents the App Store offer code redemption sheet in the given scene.
    @available(iOS 16.0, *)
    public func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        let managers: Managers = try requireManagers()

        try await managers.purchasesManager.presentOfferCodeRedeemSheet(in: scene)
    }
    #endif

    /// Sends the historical App Store transactions to Qonversion once per
    /// install. Call it right after the first launch of the app version that
    /// integrates the SDK, so the existing subscribers' data reaches the
    /// analytics.
    public func syncHistoricalData() {
        guard let managers: Managers = currentManagers() else { return }

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
        guard let managers: Managers = currentManagers() else { return }

        try? await managers.userPropertiesManager.sendProperties(force: true)
    }

    /// Whether the bundled fallback file (`qonversion_ios_fallbacks.json`) is
    /// present in the app bundle and parses. Use in debug builds to verify the
    /// offline fallback setup.
    public func isFallbackFileAccessible() -> Bool {
        guard let managers: Managers = currentManagers() else { return false }

        return managers.productsManager.isFallbackFileAccessible()
    }

    /// Collects Apple Search Ads Attribution data
    /// Available only for iOS 14.3+
    /// See details in the [Apple official documentation](https://developer.apple.com/documentation/iad/setting-up-apple-search-ads-attribution)
    public func collectAppleSearchAdsAttribution() {
        currentManagers()?.userPropertiesManager.collectAppleSearchAdsAttribution()
    }
    
    /// Collects advertising ID
    /// On iOS 14.5+, after requesting the app tracking permission using ATT, you need to notify Qonversion if tracking is allowed and IDFA is available.
    public func collectAdvertisingId() {
        currentManagers()?.deviceManager.collectAdvertisingId()
    }
    
    /// Sets Qonversion defined user properties, like email or appsFlyer user ID.
    /// - Note that using ``Qonversion/Qonversion/UserPropertyKey/custom`` here will do nothing.
    /// - To set custom user property, use ``Qonversion/Qonversion/setCustomUserProperty(_:key:)``  instead.
    /// - Parameters:
    ///   - userProperty: Property value
    ///   - key: Defined enum key
    public func setUserProperty(_ userProperty: String, key: UserPropertyKey) {
        guard let managers: Managers = currentManagers() else { return }

        managers.userPropertiesManager.setUserProperty(key: key, value: userProperty)
    }
    
    /// Sets custom user property
    /// - Parameters:
    ///   - userProperty: Property value
    ///   - key: Custom property key
    public func setCustomUserProperty(_ userProperty: String, key: String) {
        guard let managers: Managers = currentManagers() else { return }

        managers.userPropertiesManager.setCustomUserProperty(key: key, value: userProperty)
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

    /// A snapshot of the graph taken under the lock. The lock is released
    /// before the caller awaits anything.
    private func currentManagers() -> Managers? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return managers
    }

    private func requireManagers() throws -> Managers {
        guard let managers: Managers = currentManagers() else { throw QonversionError.initializationError() }

        return managers
    }

    private init() { }
}
