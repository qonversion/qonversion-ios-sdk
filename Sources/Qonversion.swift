//
//  Qonversion.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation
import StoreKit

/// An entry point to use Qonversion SDK.
// @unchecked: the managers are written once in initialize() and the SDK
// contract requires initialize() before any other call.
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
        let assembly: QonversionAssembly = QonversionAssembly(apiKey: configuration.apiKey, userDefaults: configuration.userDefaults, launchMode: configuration.launchMode, baseURL: configuration.baseURL, entitlementsCacheLifetime: configuration.entitlementsCacheLifetime, logLevel: configuration.logLevel)
        Qonversion.shared.userManager = assembly.userManager()
        Qonversion.shared.userPropertiesManager = assembly.userPropertiesManager()
        Qonversion.shared.deviceManager = assembly.deviceManager()
        Qonversion.shared.productsManager = assembly.productsManager()
        Qonversion.shared.remoteConfigManager = assembly.remoteConfigManager()
        Qonversion.shared.purchasesManager = assembly.purchasesManager()
        Qonversion.shared.entitlementsManager = assembly.entitlementsManager()

        // Start consuming out-of-band transaction updates (renewals, refunds,
        // Ask to Buy approvals, purchases on other devices).
        Qonversion.shared.purchasesManager?.startObservingTransactions()

        // Re-report transactions left unfinished by previous sessions
        // (no-op in Analytics mode).
        Task {
            await Qonversion.shared.purchasesManager?.processUnfinishedTransactions()
        }

        // In subscription-management mode the SDK needs the product →
        // permissions mapping for local entitlements calculation; refresh the
        // persistent cache on every launch.
        if configuration.launchMode == .subscriptionManagement {
            Task {
                await Qonversion.shared.productsManager?.loadProductPermissions()
            }
        }

        // Warm up the user gate: create the backend user early so the first
        // data-sending call doesn't pay for it. Failure is fine — the gate
        // retries on the next demand.
        Task {
            try? await Qonversion.shared.userManager?.obtainUser()
        }

        return Qonversion.shared
    }
    
    /// Links the current Qonversion user to your unique user id and shares purchase data.
    /// If the given id is already linked to another Qonversion user, the SDK switches to that user.
    /// - Parameter userId: your unique user id.
    /// - Returns: the current ``Qonversion/Qonversion/User``.
    @discardableResult
    public func identify(_ userId: String) async throws -> Qonversion.User {
        guard let userManager else { throw QonversionError.initializationError() }

        return try await userManager.identify(userId)
    }

    /// Unlinks the current user from your unique user id and resets to a
    /// fresh anonymous user. Await the call before the next identify — the
    /// reset is guaranteed to be finished when it returns.
    public func logout() async {
        guard let userManager else { return }

        await userManager.logout()
    }

    /// Returns information about the current Qonversion user.
    public func userInfo() async throws -> Qonversion.User {
        guard let userManager else { throw QonversionError.initializationError() }

        return try await userManager.userInfo()
    }

    /// Returns Qonversion products in association with App Store products.
    /// - Throws: Possible error during the products request or Qonversion initialization error.
    public func products() async throws -> [Qonversion.Product] {
        guard let productsManager else { throw QonversionError.initializationError() }

        return try await productsManager.products()
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
        guard let purchasesManager else { throw QonversionError.initializationError() }

        return try await purchasesManager.purchase(product, options: options)
    }

    /// Reports purchases made by your own StoreKit 2 code so Qonversion can
    /// track them (Analytics mode). Pass the verification results you receive
    /// from `Product.PurchaseResult` or `Transaction.updates`. The SDK never
    /// finishes these transactions — your app owns their lifecycle.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public func handlePurchases(_ verificationResults: [VerificationResult<StoreKit.Transaction>]) async {
        guard let purchasesManager else { return }

        await purchasesManager.handle(purchasedTransactions: verificationResults)
    }

    /// Requests a signed promotional offer for the product's subscription
    /// discount. Pass the result to ``purchase(_:options:)`` via
    /// ``PurchaseOptions/promoOffer``.
    public func getPromotionalOffer(for product: Qonversion.Product, discountId: String) async throws -> Qonversion.PromotionalOffer {
        guard let purchasesManager else { throw QonversionError.initializationError() }

        return try await purchasesManager.promotionalOffer(for: product, discountId: discountId)
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
        guard let purchasesManager else { return AsyncStream { $0.finish() } }

        return purchasesManager.promoPurchaseIntents()
    }

    /// A stream of entitlements refreshed after the SDK processes an
    /// out-of-band transaction in subscription-management mode (Ask to Buy
    /// approvals, renewals, purchases on other devices). Like StoreKit's
    /// `Transaction.updates`, every access returns an independent stream:
    ///
    ///     for await entitlements in Qonversion.shared.entitlementsUpdates { ... }
    public var entitlementsUpdates: AsyncStream<[String: Qonversion.Entitlement]> {
        guard let purchasesManager else { return AsyncStream { $0.finish() } }

        return purchasesManager.entitlementsUpdates()
    }

    /// Restores the user's purchases and returns the entitlements.
    /// When the backend is unreachable, entitlements are calculated locally.
    @discardableResult
    public func restore() async throws -> [String: Qonversion.Entitlement] {
        guard let purchasesManager else { throw QonversionError.initializationError() }

        return try await purchasesManager.restore()
    }

    /// Returns the user's entitlements keyed by entitlement id.
    /// When the backend is unreachable (5xx / connection issues), entitlements
    /// are calculated locally from StoreKit data and the cached mapping.
    public func checkEntitlements() async throws -> [String: Qonversion.Entitlement] {
        guard let entitlementsManager else { throw QonversionError.initializationError() }

        return try await entitlementsManager.entitlements()
    }

    /// Collects Apple Search Ads Attribution data
    /// Available only for iOS 14.3+
    /// See details in the [Apple official documentation](https://developer.apple.com/documentation/iad/setting-up-apple-search-ads-attribution)
    public func collectAppleSearchAdsAttribution() {
        userPropertiesManager?.collectAppleSearchAdsAttribution()
    }
    
    /// Collects advertising ID
    /// On iOS 14.5+, after requesting the app tracking permission using ATT, you need to notify Qonversion if tracking is allowed and IDFA is available.
    public func collectAdvertisingId() {
        deviceManager?.collectAdvertisingId()
    }
    
    /// Sets Qonversion defined user properties, like email or appsFlyer user ID.
    /// - Note that using ``Qonversion/Qonversion/UserPropertyKey/custom`` here will do nothing.
    /// - To set custom user property, use ``Qonversion/Qonversion/setCustomUserProperty(_:key:)``  instead.
    /// - Parameters:
    ///   - userProperty: Property value
    ///   - key: Defined enum key
    public func setUserProperty(_ userProperty: String, key: UserPropertyKey) {
        guard let userPropertiesManager else { return }
        
        userPropertiesManager.setUserProperty(key: key, value: userProperty)
    }
    
    /// Sets custom user property
    /// - Parameters:
    ///   - userProperty: Property value
    ///   - key: Custom property key
    public func setCustomUserProperty(_ userProperty: String, key: String) {
        guard let userPropertiesManager else { return }
        
        userPropertiesManager.setCustomUserProperty(key: key, value: userProperty)
    }
    
    /// This method returns all the properties, set for the current Qonversion user.
    /// All set properties are sent to the server with delay, so if you call
    /// this function right after setting some property, it may not be included in the result.
    /// - Returns: ``Qonversion/Qonversion/UserProperties`` that contains all the properties, set for the current Qonversion user.
    /// - Throws: Possible error during the properties request or Qonversion initialization error if the method is called before initialization.
    public func userProperties() async throws -> UserProperties {
        guard let userPropertiesManager else { throw QonversionError.initializationError() }
        
        return try await userPropertiesManager.userProperties()
    }
    
    /// Returns Qonversion default remote config object or one defined by the context key.
    /// Use this function to get the remote config with specific payload and experiment info.
    /// - Parameters:
    ///   - contextKey: Context key to get remote config for
    /// - Returns: ``Qonversion/Qonversion/RemoteConfig`` for the specified context key or default one if no key provided.
    /// - Throws: Possible error during the remote config request or Qonversion initialization error if the method is called before initialization.
    public func remoteConfig(contextKey: String? = nil) async throws -> Qonversion.RemoteConfig {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return try await remoteConfigManager.loadRemoteConfig(contextKey: contextKey)
    }
    
    /// Returns Qonversion remote config objects for all existing context key (including empty one).
    /// Use this function to get the remote configs with specific payload and experiment info.
    /// - Returns: ``Qonversion/Qonversion/RemoteConfigList`` with all the remote configs for the current user.
    /// - Throws: Possible error during the remote config request or Qonversion initialization error if the method is called before initialization.
    public func remoteConfigList() async throws -> Qonversion.RemoteConfigList {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return try await remoteConfigManager.loadRemoteConfigList()
    }

    /// Returns Qonversion remote config objects by a list of context keys.
    /// Use this function to get the remote configs with specific payload and experiment info.
    /// - Parameters:
    ///   - contextKeys:list of context keys to get remote configs for.
    ///   - includeEmptyContextKey: set to true if you want to include remote config with empty context key to the result.
    /// - Returns: ``Qonversion/Qonversion/RemoteConfigList`` with the requested remote configs for the current user.
    /// - Throws: Possible error during the remote config list request or Qonversion initialization error if the method is called before initialization.
    public func remoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        return try await remoteConfigManager.loadRemoteConfigList(contextKeys: contextKeys, includeEmptyContextKey: includeEmptyContextKey)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to attach the user to the remote configuration.
    /// - Parameters:
    ///   - id: identifier of the remote configuration.
    /// - Throws: Possible error during the attaching process or Qonversion initialization error if the method is called before initialization.
    public func attachUserToRemoteConfiguration(id: String) async throws {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        try await remoteConfigManager.attachUserToRemoteConfig(id: id)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to detach the user from the remote configuration.
    /// - Parameters:
    ///   - id: identifier of the remote configuration.
    /// - Throws: Possible error during the detaching process or Qonversion initialization error if the method is called before initialization.
    public func detachUserFromRemoteConfiguration(id: String) async throws {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        try await remoteConfigManager.detachUserFromRemoteConfig(id: id)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to attach the user to the experiment.
    /// - Parameters:
    ///   - id: identifier of the experiment
    ///   - groupId: identifier of the experiment group
    /// - Throws: Possible error during the attaching process or Qonversion initialization error if the method is called before initialization.
    public func attachUserToExperiment(id: String, groupId: String) async throws {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        try await remoteConfigManager.attachUserToExperiment(id: id, groupId: groupId)
    }

    /// This function should be used for the test purposes only. Do not forget to delete the usage of this function before the release.
    /// Use this function to detach the user to the experiment.
    /// - Parameters:
    ///   - id: identifier of the experiment
    /// - Throws: Possible error during the detaching process or Qonversion initialization error if the method is called before initialization.
    public func detachUserFromExperiment(id: String) async throws {
        guard let remoteConfigManager else { throw QonversionError.initializationError() }

        try await remoteConfigManager.detachUserFromExperiment(id: id)
    }

    // MARK: - Private
    private var userManager: UserManagerInterface?
    private var purchasesManager: PurchasesManagerInterface?
    private var entitlementsManager: EntitlementsManagerInterface?
    private var userPropertiesManager: UserPropertiesManagerInterface?
    private var deviceManager: DeviceManagerInterface?
    private var productsManager: ProductsManagerInterface?
    private var remoteConfigManager: RemoteConfigManagerInterface?
    
    private init() { }
}
