//
//  OtherView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct OtherView: View {

    @EnvironmentObject var appState: AppState
    @State private var fallbackAccessible: Bool?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                fallbackSection
                iOSOnlySection
                promoSection
            }
            .padding()
        }
        .navigationTitle("Other")
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .messageAlerts()
    }

    private var fallbackSection: some View {
        Card(title: "Fallback File") {
            HStack {
                Text("Accessibility:")
                    .font(.subheadline)

                Circle()
                    .fill(fallbackStatusColor)
                    .frame(width: 12, height: 12)

                Text(fallbackStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ActionButton(title: "Check Fallback File Accessibility", color: .blue) {
                fallbackAccessible = appState.checkFallbackFileAccessibility()
            }

            Text("Reads qonversion_ios_fallbacks.json from the app bundle. It backs products and entitlements when the API cannot be reached.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var iOSOnlySection: some View {
        Card(title: "iOS-Only Methods") {
            ActionButton(title: "Collect Advertising ID", color: .purple) {
                appState.collectAdvertisingId()
            }

            ActionButton(title: "Collect Apple Search Ads Attribution", color: .green) {
                appState.collectAppleSearchAdsAttribution()
            }

            ActionButton(title: "Present Code Redemption Sheet", color: .orange) {
                appState.presentCodeRedemptionSheet()
            }
        }
    }

    /// The promo delegate is gone: an App Store promoted purchase now arrives
    /// on the promoPurchaseIntents stream, which the app subscribes to at
    /// launch. Nothing is charged until purchase() is called on the intent, so
    /// an app is free to show its own screen first.
    private var promoSection: some View {
        Card(title: "Promo Purchases") {
            ActiveBadge(text: "Promo purchase intents are observed from launch")

            Text("Trigger one from App Store Connect's promoted in-app purchases. The intent appears in the SDK Events list on the Entitlements tab, and this sample completes it immediately.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var fallbackStatusColor: Color {
        switch fallbackAccessible {
        case .some(true):
            return .green
        case .some(false):
            return .red
        case .none:
            return .gray
        }
    }

    private var fallbackStatusText: String {
        switch fallbackAccessible {
        case .some(true):
            return "Accessible"
        case .some(false):
            return "Not Accessible"
        case .none:
            return "Not Checked"
        }
    }
}

#Preview {
    NavigationView {
        OtherView()
            .environmentObject(AppState())
    }
}
