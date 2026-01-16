//
//  AppState.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

@MainActor
class AppState: ObservableObject {
    @Published var products: [String: Qonversion.Product] = [:]
    @Published var entitlements: [String: Qonversion.Entitlement] = [:]
    @Published var offerings: Qonversion.Offerings?
    @Published var remoteConfigs: Qonversion.RemoteConfigList?
    @Published var userInfo: Qonversion.User?
    @Published var userProperties: Qonversion.UserProperties?
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    @Published var noCodesEvents: [String] = []
    
    @Published var selectedProduct: Qonversion.Product?
    @Published var selectedEntitlement: Qonversion.Entitlement?
    
    init() {
        loadUserInfo()
    }
    
    // MARK: - User Info
    func loadUserInfo() {
        Qonversion.shared().userInfo { [weak self] user, error in
            Task { @MainActor in
                if let user = user {
                    self?.userInfo = user
                } else if let error = error {
                    print("❌ Failed to load user info: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Products
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().products { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else {
                        self?.products = result
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Entitlements
    func loadEntitlements() async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().checkEntitlements { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else {
                        self?.entitlements = result
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    func restore() async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().restore { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else {
                        self?.entitlements = result
                        self?.successMessage = "Purchases restored successfully!"
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    func syncHistoricalData() {
        Qonversion.shared().syncHistoricalData()
        successMessage = "Historical data sync started"
    }
    
    func syncStoreKit2Purchases() {
        QonversionSwift.shared.syncStoreKit2Purchases()
        successMessage = "StoreKit 2 purchases synced"
    }
    
    // MARK: - Offerings
    func loadOfferings() async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().offerings { [weak self] result, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else {
                        self?.offerings = result
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Purchase
    func purchase(_ product: Qonversion.Product) async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().purchase(product) { [weak self] result in
                Task { @MainActor in
                    if result.isSuccessful {
                        if let entitlements = result.entitlements {
                            for (key, value) in entitlements {
                                self?.entitlements[key] = value
                            }
                        }
                        self?.successMessage = "Purchase successful!"
                    } else if result.isCanceledByUser {
                        // User canceled, no error message needed
                    } else if result.isPending {
                        self?.successMessage = "Purchase is pending..."
                    } else if result.isError {
                        self?.errorMessage = result.error?.localizedDescription ?? "Purchase failed"
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Remote Configs
    func loadRemoteConfig(contextKey: String?) async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            if let key = contextKey {
                Qonversion.shared().remoteConfig(contextKey: key) { [weak self] config, error in
                    Task { @MainActor in
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                        } else if let config = config {
                            let list = Qonversion.RemoteConfigList()
                            list.remoteConfigs = [config]
                            self?.remoteConfigs = list
                        }
                        self?.isLoading = false
                        continuation.resume()
                    }
                }
            } else {
                Qonversion.shared().remoteConfig { [weak self] config, error in
                    Task { @MainActor in
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                        } else if let config = config {
                            let list = Qonversion.RemoteConfigList()
                            list.remoteConfigs = [config]
                            self?.remoteConfigs = list
                        }
                        self?.isLoading = false
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func loadRemoteConfigList(contextKeys: [String]?) async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            if let keys = contextKeys, !keys.isEmpty {
                Qonversion.shared().remoteConfigList(contextKeys: keys, includeEmptyContextKey: true) { [weak self] result, error in
                    Task { @MainActor in
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                        } else {
                            self?.remoteConfigs = result
                        }
                        self?.isLoading = false
                        continuation.resume()
                    }
                }
            } else {
                Qonversion.shared().remoteConfigList { [weak self] result, error in
                    Task { @MainActor in
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                        } else {
                            self?.remoteConfigs = result
                        }
                        self?.isLoading = false
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func attachToExperiment(experimentId: String, groupId: String) async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().attachUser(toExperiment: experimentId, groupId: groupId) { [weak self] success, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else if success {
                        self?.successMessage = "Attached to experiment successfully!"
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    func detachFromExperiment(experimentId: String) async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().detachUser(fromExperiment: experimentId) { [weak self] success, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else if success {
                        self?.successMessage = "Detached from experiment successfully!"
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - User
    func identify(userId: String) async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().identify(userId) { [weak self] user, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else if let user = user {
                        self?.userInfo = user
                        self?.successMessage = "User identified successfully!"
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    func logout() {
        Qonversion.shared().logout()
        loadUserInfo()
        successMessage = "Logged out successfully!"
    }
    
    func loadUserProperties() async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            Qonversion.shared().userProperties { [weak self] properties, error in
                Task { @MainActor in
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else {
                        self?.userProperties = properties
                    }
                    self?.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    func setUserProperty(_ key: Qonversion.UserPropertyKey, value: String) {
        Qonversion.shared().setUserProperty(key, value: value)
        successMessage = "User property set!"
    }
    
    func setCustomUserProperty(_ key: String, value: String) {
        Qonversion.shared().setCustomUserProperty(key, value: value)
        successMessage = "Custom user property set!"
    }
    
    func sendAttribution(data: [String: Any], provider: Qonversion.AttributionProvider) {
        Qonversion.shared().attribution(data, from: provider)
        successMessage = "Attribution data sent!"
    }
    
    // MARK: - Other
    func checkFallbackFileAccessibility() {
        let accessible = Qonversion.shared().isFallbackFileAccessible()
        successMessage = "Fallback file accessible: \(accessible)"
    }
    
    func collectAdvertisingId() {
        Qonversion.shared().collectAdvertisingId()
        successMessage = "Advertising ID collected!"
    }
    
    func collectAppleSearchAdsAttribution() {
        Qonversion.shared().collectAppleSearchAdsAttribution()
        successMessage = "Apple Search Ads attribution collected!"
    }
    
    func presentCodeRedemptionSheet() {
        Qonversion.shared().presentCodeRedemptionSheet()
        successMessage = "Code redemption sheet presented!"
    }
    
    // MARK: - Clear messages
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    // MARK: - NoCodes Events
    func addNoCodesEvent(_ event: String) {
        noCodesEvents.append(event)
    }
}
