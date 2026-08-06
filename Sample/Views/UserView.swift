//
//  UserView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct UserView: View {

    @EnvironmentObject var appState: AppState

    @State private var identityId = ""
    @State private var selectedPropertyKey: Qonversion.UserPropertyKey = .email
    @State private var customPropertyKey = ""
    @State private var propertyValue = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                userInfoSection
                identitySection
                userPropertiesSection
                attributionSection
            }
            .padding()
        }
        .navigationTitle("User")
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .messageAlerts()
    }

    @ViewBuilder
    private var userInfoSection: some View {
        if let userInfo: Qonversion.User = appState.userInfo {
            Card(title: "Current User") {
                DetailRow(label: "Qonversion ID", value: userInfo.id)
                DetailRow(label: "Identity ID", value: userInfo.identityId ?? "Anonymous")
                DetailRow(label: "Created", value: formatDate(userInfo.creationDate))
                DetailRow(label: "Original App Version", value: userInfo.originalAppVersion ?? "N/A")
            }
        }
    }

    private var identitySection: some View {
        Card(title: "Identity") {
            TextField("Identity ID", text: $identityId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)

            HStack(spacing: 12) {
                ActionButton(title: "Identify", color: .blue) {
                    guard !identityId.isEmpty else {
                        appState.errorMessage = "Please enter Identity ID"
                        return
                    }
                    Task { await appState.identify(userId: identityId) }
                }

                ActionButton(title: "Logout", color: .red) {
                    Task {
                        await appState.logout()
                        identityId = ""
                    }
                }
            }

            ActionButton(title: "Refresh User Info", color: .green) {
                Task { await appState.loadUserInfo() }
            }
        }
    }

    private var userPropertiesSection: some View {
        Card(title: "User Properties") {
            ActionButton(title: "Load User Properties", color: .purple) {
                Task { await appState.loadUserProperties() }
            }

            propertiesDisplay

            Divider()

            Text("Set Property")
                .font(.subheadline)
                .fontWeight(.medium)

            propertyKeyPicker

            TextField("Property Value", text: $propertyValue)
                .textFieldStyle(.roundedBorder)

            setPropertyButton

            // Properties are batched: setting one only queues it, and the
            // request leaves five seconds later. This is the button to press
            // when watching for the POST.
            ActionButton(title: "Force Send Properties", color: .indigo) {
                Task { await appState.forceSendProperties() }
            }

            Text("Setting a property queues it. The batch is sent 5 seconds later, when the app is backgrounded, or immediately via Force Send.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var propertiesDisplay: some View {
        if let properties: Qonversion.UserProperties = appState.userProperties {
            if properties.properties.isEmpty {
                Text("No properties set")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(properties.properties, id: \.key) { property in
                    HStack {
                        Text(property.key)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(property.value)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var propertyKeyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Property Key", selection: $selectedPropertyKey) {
                ForEach(UserView.selectableKeys, id: \.self) { key in
                    Text(displayName(for: key)).tag(key)
                }
            }
            .pickerStyle(.menu)

            if selectedPropertyKey == .custom {
                TextField("Custom Property Key", text: $customPropertyKey)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
            }
        }
    }

    private var setPropertyButton: some View {
        ActionButton(title: "Set Property", color: .orange) {
            guard !propertyValue.isEmpty else {
                appState.errorMessage = "Please enter property value"
                return
            }

            if selectedPropertyKey == .custom {
                guard !customPropertyKey.isEmpty else {
                    appState.errorMessage = "Please enter custom property key"
                    return
                }
                appState.setCustomUserProperty(customPropertyKey, value: propertyValue)
            } else {
                appState.setUserProperty(selectedPropertyKey, value: propertyValue)
            }
        }
    }

    /// The old sample sent third-party attribution payloads from here. That
    /// call is not part of this SDK's surface — Apple Search Ads is the one
    /// attribution source it collects, and it does so itself.
    private var attributionSection: some View {
        Card(title: "Attribution") {
            Text("Third-party attribution (AppsFlyer, Branch, Adjust) has no public method in this SDK. Their identifiers are sent as user properties instead — set _q_appsflyer_user_id, _q_adjust_adid or _q_advertising_id above.")
                .font(.caption)
                .foregroundColor(.secondary)

            ActionButton(title: "Collect Apple Search Ads Attribution", color: .pink) {
                appState.collectAppleSearchAdsAttribution()
            }
        }
    }

    /// Listed by hand: the SDK's key enum is not CaseIterable, and .custom has
    /// to lead so the picker opens on something that needs no explanation.
    static let selectableKeys: [Qonversion.UserPropertyKey] = [
        .custom,
        .email,
        .name,
        .userId,
        .advertisingId,
        .kochavaDeviceId,
        .appsFlyerUserId,
        .adjustAdId,
        .firebaseAppInstanceId,
        .appSetId,
        .appMetricaDeviceId,
        .appMetricaUserProfileId,
        .pushWooshHwId,
        .pushWooshUserId,
        .facebookAttribution,
        .tenjinAnalyticsInstallationId,
    ]

    private func displayName(for key: Qonversion.UserPropertyKey) -> String {
        switch key {
        case .custom:
            return "Custom"
        case .email:
            return "Email"
        case .name:
            return "Name"
        case .kochavaDeviceId:
            return "Kochava Device ID"
        case .appsFlyerUserId:
            return "AppsFlyer User ID"
        case .adjustAdId:
            return "Adjust Ad ID"
        case .advertisingId:
            return "Advertising ID"
        case .userId:
            return "User ID"
        case .firebaseAppInstanceId:
            return "Firebase App Instance ID"
        case .appSetId:
            return "App Set ID"
        case .appMetricaDeviceId:
            return "AppMetrica Device ID"
        case .appMetricaUserProfileId:
            return "AppMetrica User Profile ID"
        case .pushWooshHwId:
            return "PushWoosh HW ID"
        case .pushWooshUserId:
            return "PushWoosh User ID"
        case .facebookAttribution:
            return "Facebook Attribution"
        case .tenjinAnalyticsInstallationId:
            return "Tenjin Analytics Installation ID"
        }
    }
}

#Preview {
    NavigationView {
        UserView()
            .environmentObject(AppState())
    }
}
