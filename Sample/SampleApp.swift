//
//  SampleApp.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

@main
struct SampleApp: App {
    @StateObject private var appState = AppState()
    
    init() {
        initializeQonversion()
        initializeNoCodes()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                // Web2App redemption (DEV-847): the redemption email opens a
                // Universal Link https://screens.qonversion.io/r/{project_uid}/{token}.
                // iOS delivers it as a browsing-web user activity. Forward the URL
                // to the SDK, which validates host + path internally (grant-first:
                // on success the backend already granted the entitlement, the SDK
                // just refreshes — no identify).
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    handleRedemption(url)
                }
        }
    }

    private func handleRedemption(_ url: URL) {
        Qonversion.shared().handleRedemptionLink(url: url) { result in
            switch result {
            case .success:
                print("✅ Redemption succeeded — entitlements refreshed")
            case .tokenExpired:
                print("⏰ Redemption token expired — offer reissue")
            case .alreadyConsumed:
                print("♻️ Redemption token already consumed")
            case .invalidToken:
                print("❌ Invalid redemption token")
            case .networkError:
                print("📡 Network error during redemption")
            case .retryable:
                print("🔁 Retryable error during redemption — try again")
            @unknown default:
                print("Redemption result: \(result.rawValue)")
            }
        }
    }
    
    private func initializeQonversion() {
        let projectKey = ConfigurationManager.getProjectKey()
        let apiUrl = ConfigurationManager.getApiUrl()
        
        let config = Qonversion.Configuration(
            projectKey: projectKey,
            launchMode: .subscriptionManagement
        )
        config.setEnvironment(.sandbox)
        config.setEntitlementsCacheLifetime(.year)
        
        if let apiUrl = apiUrl {
            config.setProxyURL(apiUrl)
        }
        
        Qonversion.initWithConfig(config)
        Qonversion.shared().setPromoPurchasesDelegate(PromoPurchasesHandler.shared)
        Qonversion.shared().collectAdvertisingId()
        QonversionSwift.shared.syncStoreKit2Purchases()
    }
    
    private func initializeNoCodes() {
        let projectKey = ConfigurationManager.getProjectKey()
        let apiUrl = ConfigurationManager.getApiUrl()
        
        var configuration = NoCodesConfiguration(projectKey: projectKey)
        if let apiUrl = apiUrl {
            configuration.proxyURL = apiUrl
        }
        NoCodes.initialize(with: configuration)
    }
}

// MARK: - Promo Purchases Handler
class PromoPurchasesHandler: NSObject, Qonversion.PromoPurchasesDelegate {
    static let shared = PromoPurchasesHandler()
    
    func shouldPurchasePromoProduct(withIdentifier productID: String, executionBlock: @escaping Qonversion.PromoPurchaseCompletionHandler) {
        print("🎁 Promo purchase received for product: \(productID)")
        let completion: Qonversion.PurchaseCompletionHandler = { result, error, canceled in
            if let error = error {
                print("❌ Promo purchase failed: \(error.localizedDescription)")
            } else if canceled {
                print("⚠️ Promo purchase was canceled")
            } else {
                print("✅ Promo purchase succeeded")
            }
        }
        executionBlock(completion)
    }
}
