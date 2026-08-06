//
//  SampleApp.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion
import NoCodes

@main
struct SampleApp: App {

    @StateObject private var appState = AppState()

    init() {
        SampleApp.initializeQonversion()
        SampleApp.initializeNoCodes()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    // The three streams are the replacement for the ObjC-era
                    // delegates. They are started once, for the lifetime of
                    // the scene, because each of them is single-subscriber:
                    // starting one per screen would leave whoever subscribed
                    // last as the only listener.
                    await appState.startObservingSDKStreams()
                }
        }
    }

    private static func initializeQonversion() {
        let projectKey: String = ConfigurationManager.getProjectKey()
        let proxyURL: String? = ConfigurationManager.getApiUrl()

        // Everything is passed at construction: the new SDK has no setters, so
        // the configuration is complete before the SDK exists. The environment
        // is no longer declared either — it is taken from the receipt.
        let configuration = Qonversion.Configuration(
            apiKey: projectKey,
            launchMode: .subscriptionManagement,
            proxyURL: proxyURL,
            entitlementsCacheLifetime: .month,
            logLevel: .verbose
        )
        Qonversion.initialize(with: configuration)

        Qonversion.shared.collectAdvertisingId()
    }

    private static func initializeNoCodes() {
        let projectKey: String = ConfigurationManager.getProjectKey()
        let proxyURL: String? = ConfigurationManager.getApiUrl()

        // No-Codes is a separate SDK with its own configuration. Sending it to
        // the same host matters: with the default it would call production
        // while the main SDK talks to a local stack, and every screen would
        // fail to load.
        let configuration = NoCodesConfiguration(
            projectKey: projectKey,
            proxyURL: proxyURL
        )
        NoCodes.initialize(with: configuration)
    }
}
