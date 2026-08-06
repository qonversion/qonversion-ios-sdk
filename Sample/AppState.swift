//
//  AppState.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

@MainActor
final class AppState: ObservableObject {

    /// Products are managed via Remote Configs — see the migration guide:
    /// https://documentation.qonversion.io/docs/migrate-offerings-to-remote-configs
    ///
    /// An array, not a dictionary: the new SDK returns the catalog in the
    /// order the backend defines it, and that order is worth keeping.
    @Published var products: [Qonversion.Product] = []
    @Published var entitlements: [String: Qonversion.Entitlement] = [:]
    /// Flattened out of RemoteConfigList: the single-config call answers with
    /// one RemoteConfig and the list call with a wrapper, and the wrapper
    /// cannot be built by hand outside the SDK.
    @Published var remoteConfigs: [Qonversion.RemoteConfig] = []
    @Published var userInfo: Qonversion.User?
    @Published var userProperties: Qonversion.UserProperties?
    @Published var introEligibility: [String: Qonversion.IntroEligibilityStatus] = [:]

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published var noCodesEvents: [String] = []
    @Published var sdkEvents: [String] = []

    init() {
        Task { await loadUserInfo() }
    }

    // MARK: - SDK streams

    /// The successor to setDeferredPurchasesListener / setPromoPurchasesDelegate.
    /// Each stream yields for as long as the app runs, so all three are consumed
    /// in parallel and never awaited one after another.
    func startObservingSDKStreams() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeEntitlementsUpdates() }
            group.addTask { await self.observeDeferredPurchases() }
            group.addTask { await self.observePromoPurchaseIntents() }
        }
    }

    private func observeEntitlementsUpdates() async {
        for await updated in Qonversion.shared.entitlementsUpdates {
            entitlements = updated
            addSDKEvent("Entitlements updated (\(updated.count))")
        }
    }

    private func observeDeferredPurchases() async {
        for await purchase in Qonversion.shared.deferredPurchases {
            for (key, value) in purchase.entitlements {
                entitlements[key] = value
            }
            addSDKEvent("Deferred purchase: \(purchase.transaction.productId)")
        }
    }

    /// An App Store promoted purchase. The intent is the permission to go
    /// ahead: nothing is charged until purchase() is called on it, so an app
    /// can show its own screen first.
    private func observePromoPurchaseIntents() async {
        for await intent in Qonversion.shared.promoPurchaseIntents {
            addSDKEvent("Promo purchase intent: \(intent.productId)")
            do {
                let result: Qonversion.PurchaseResult = try await intent.purchase()
                entitlements = result.entitlements
                successMessage = "Promo purchase completed"
            } catch {
                report(error, whenCancelled: "Promo purchase cancelled")
            }
        }
    }

    // MARK: - User info

    func loadUserInfo() async {
        do {
            userInfo = try await Qonversion.shared.userInfo()
        } catch {
            print("❌ Failed to load user info: \(error.localizedDescription)")
        }
    }

    // MARK: - Products

    func loadProducts() async {
        await run {
            self.products = try await Qonversion.shared.products()
        }
    }

    /// Only meaningful for products with a trial or an introductory offer; the
    /// answer comes from StoreKit, so it needs the store products loaded.
    func loadIntroEligibility() async {
        let ids: [String] = products.map(\.qonversionId)
        guard !ids.isEmpty else {
            errorMessage = "Load the products first"
            return
        }

        await run {
            self.introEligibility = try await Qonversion.shared.checkTrialIntroEligibility(ids)
        }
    }

    // MARK: - Entitlements

    func loadEntitlements() async {
        await run {
            self.entitlements = try await Qonversion.shared.checkEntitlements()
        }
    }

    func restore() async {
        await run {
            self.entitlements = try await Qonversion.shared.restore()
            self.successMessage = "Purchases restored successfully!"
        }
    }

    func syncHistoricalData() {
        Qonversion.shared.syncHistoricalData()
        successMessage = "Historical data sync started"
    }

    // MARK: - Purchase

    func purchase(_ product: Qonversion.Product) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result: Qonversion.PurchaseResult = try await Qonversion.shared.purchase(product)
            entitlements = result.entitlements
            successMessage = "Purchase successful!"
        } catch {
            // A cancellation is a normal outcome of a purchase, not a failure
            // to report — the old sample checked result.isCanceledByUser for
            // the same reason.
            report(error, whenCancelled: nil, whenPending: "Purchase is pending…")
        }
    }

    // MARK: - Remote configs

    func loadRemoteConfig(contextKey: String?) async {
        await run {
            let config: Qonversion.RemoteConfig = try await Qonversion.shared.remoteConfig(contextKey: contextKey)
            self.remoteConfigs = [config]
        }
    }

    func loadRemoteConfigList(contextKeys: [String]?) async {
        await run {
            let list: Qonversion.RemoteConfigList
            if let keys: [String] = contextKeys, !keys.isEmpty {
                list = try await Qonversion.shared.remoteConfigList(contextKeys: keys, includeEmptyContextKey: true)
            } else {
                list = try await Qonversion.shared.remoteConfigList()
            }
            self.remoteConfigs = list.remoteConfigs
        }
    }

    func attachToExperiment(experimentId: String, groupId: String) async {
        await run {
            try await Qonversion.shared.attachUserToExperiment(id: experimentId, groupId: groupId)
            self.successMessage = "Attached to experiment successfully!"
        }
    }

    func detachFromExperiment(experimentId: String) async {
        await run {
            try await Qonversion.shared.detachUserFromExperiment(id: experimentId)
            self.successMessage = "Detached from experiment successfully!"
        }
    }

    func attachToRemoteConfiguration(id: String) async {
        await run {
            try await Qonversion.shared.attachUserToRemoteConfiguration(id: id)
            self.successMessage = "Attached to remote configuration successfully!"
        }
    }

    func detachFromRemoteConfiguration(id: String) async {
        await run {
            try await Qonversion.shared.detachUserFromRemoteConfiguration(id: id)
            self.successMessage = "Detached from remote configuration successfully!"
        }
    }

    // MARK: - User

    func identify(userId: String) async {
        await run {
            self.userInfo = try await Qonversion.shared.identify(userId)
            self.successMessage = "User identified successfully!"
        }
    }

    func logout() async {
        await Qonversion.shared.logout()
        await loadUserInfo()
        successMessage = "Logged out successfully!"
    }

    func loadUserProperties() async {
        await run {
            self.userProperties = try await Qonversion.shared.userProperties()
        }
    }

    func setUserProperty(_ key: Qonversion.UserPropertyKey, value: String) {
        Qonversion.shared.setUserProperty(key: key, value: value)
        successMessage = "Property queued — it is sent within 5 seconds, or right away via Force Send"
    }

    func setCustomUserProperty(_ key: String, value: String) {
        Qonversion.shared.setCustomUserProperty(key: key, value: value)
        successMessage = "Property queued — it is sent within 5 seconds, or right away via Force Send"
    }

    /// Skips the batching delay. Useful when watching the request go out.
    func forceSendProperties() async {
        isLoading = true
        await Qonversion.shared.forceSendProperties()
        isLoading = false
        successMessage = "Properties sent"
    }

    // MARK: - Other

    func checkFallbackFileAccessibility() -> Bool {
        let accessible: Bool = Qonversion.shared.isFallbackFileAccessible()
        successMessage = "Fallback file accessible: \(accessible)"

        return accessible
    }

    func collectAdvertisingId() {
        Qonversion.shared.collectAdvertisingId()
        successMessage = "Advertising ID collected!"
    }

    func collectAppleSearchAdsAttribution() {
        Qonversion.shared.collectAppleSearchAdsAttribution()
        successMessage = "Apple Search Ads attribution collected!"
    }

    func presentCodeRedemptionSheet() {
        Qonversion.shared.presentCodeRedemptionSheet()
        successMessage = "Code redemption sheet presented!"
    }

    // MARK: - Messages and events

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    func addNoCodesEvent(_ event: String) {
        noCodesEvents.append(event)
    }

    func addSDKEvent(_ event: String) {
        sdkEvents.append(event)
    }
}

// MARK: - Private

private extension AppState {

    /// The loading flag and the error handling every call shares.
    func run(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turns a thrown error into the right user-facing message. A cancelled
    /// purchase gets no error alert; `whenCancelled` is the optional note to
    /// show instead.
    func report(_ error: Error, whenCancelled: String?, whenPending: String? = nil) {
        guard let qonversionError = error as? QonversionError else {
            errorMessage = error.localizedDescription
            return
        }

        switch qonversionError.type {
        case .purchaseCancelled:
            successMessage = whenCancelled
        case .purchasePending:
            successMessage = whenPending ?? "Purchase is pending…"
        default:
            errorMessage = qonversionError.message
        }
    }
}
