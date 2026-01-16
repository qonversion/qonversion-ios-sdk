//
//  UserView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct UserView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var identityId = ""
    @State private var selectedPropertyKey: UserPropertyKeyOption = .email
    @State private var customPropertyKey = ""
    @State private var propertyValue = ""
    @State private var attributionData = ""
    @State private var selectedAttributionProvider: Qonversion.AttributionProvider = .appsFlyer
    
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
        .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
            Button("OK") { appState.clearMessages() }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert("Success", isPresented: .constant(appState.successMessage != nil)) {
            Button("OK") { appState.clearMessages() }
        } message: {
            Text(appState.successMessage ?? "")
        }
    }
    
    @ViewBuilder
    private var userInfoSection: some View {
        if let userInfo = appState.userInfo {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current User")
                    .font(.headline)
                
                DetailRow(label: "Qonversion ID", value: userInfo.qonversionId)
                DetailRow(label: "Identity ID", value: userInfo.identityId ?? "Anonymous")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identity")
                .font(.headline)
            
            TextField("Identity ID", text: $identityId)
                .textFieldStyle(.roundedBorder)
            
            HStack(spacing: 12) {
                ActionButton(title: "Identify", color: .blue) {
                    guard !identityId.isEmpty else {
                        appState.errorMessage = "Please enter Identity ID"
                        return
                    }
                    Task { await appState.identify(userId: identityId) }
                }
                
                ActionButton(title: "Logout", color: .red) {
                    appState.logout()
                    identityId = ""
                }
            }
            
            ActionButton(title: "Refresh User Info", color: .green) {
                appState.loadUserInfo()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var userPropertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("User Properties")
                .font(.headline)
            
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
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var propertiesDisplay: some View {
        if let properties = appState.userProperties {
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
                ForEach(UserPropertyKeyOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            
            if selectedPropertyKey == .custom {
                TextField("Custom Property Key", text: $customPropertyKey)
                    .textFieldStyle(.roundedBorder)
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
            } else if let key = selectedPropertyKey.qonversionKey {
                appState.setUserProperty(key, value: propertyValue)
            }
        }
    }
    
    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attribution")
                .font(.headline)
            
            Text("Attribution Data (JSON)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextEditor(text: $attributionData)
                .frame(height: 80)
                .padding(4)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            
            attributionProviderPicker
            
            sendAttributionButton
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var attributionProviderPicker: some View {
        Picker("Attribution Provider", selection: $selectedAttributionProvider) {
            Text("AppsFlyer").tag(Qonversion.AttributionProvider.appsFlyer)
            Text("Branch").tag(Qonversion.AttributionProvider.branch)
            Text("Adjust").tag(Qonversion.AttributionProvider.adjust)
            Text("Apple Search Ads").tag(Qonversion.AttributionProvider.appleSearchAds)
            Text("Apple Ad Services").tag(Qonversion.AttributionProvider.appleAdServices)
        }
        .pickerStyle(.menu)
    }
    
    private var sendAttributionButton: some View {
        ActionButton(title: "Send Attribution", color: .pink) {
            guard !attributionData.isEmpty else {
                appState.errorMessage = "Please enter attribution data"
                return
            }
            
            guard let data = attributionData.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                appState.errorMessage = "Invalid JSON format"
                return
            }
            
            appState.sendAttribution(data: json, provider: selectedAttributionProvider)
        }
    }
}

// MARK: - User Property Key Options
enum UserPropertyKeyOption: String, CaseIterable {
    case custom
    case email
    case name
    case kochavaDeviceId
    case appsFlyerUserId
    case adjustAdId
    case advertisingId
    case userID
    case firebaseAppInstanceId
    case appSetId
    case appMetricaDeviceId
    case appMetricaUserProfileId
    case pushWooshHwId
    case pushWooshUserId
    case facebookAttribution
    
    var displayName: String {
        switch self {
        case .custom: return "Custom"
        case .email: return "Email"
        case .name: return "Name"
        case .kochavaDeviceId: return "Kochava Device ID"
        case .appsFlyerUserId: return "AppsFlyer User ID"
        case .adjustAdId: return "Adjust Ad ID"
        case .advertisingId: return "Advertising ID"
        case .userID: return "User ID"
        case .firebaseAppInstanceId: return "Firebase App Instance ID"
        case .appSetId: return "App Set ID"
        case .appMetricaDeviceId: return "AppMetrica Device ID"
        case .appMetricaUserProfileId: return "AppMetrica User Profile ID"
        case .pushWooshHwId: return "PushWoosh HW ID"
        case .pushWooshUserId: return "PushWoosh User ID"
        case .facebookAttribution: return "Facebook Attribution"
        }
    }
    
    var qonversionKey: Qonversion.UserPropertyKey? {
        switch self {
        case .custom: return nil
        case .email: return Qonversion.UserPropertyKey.email
        case .name: return Qonversion.UserPropertyKey.name
        case .kochavaDeviceId: return Qonversion.UserPropertyKey.kochavaDeviceID
        case .appsFlyerUserId: return Qonversion.UserPropertyKey.appsFlyerUserID
        case .adjustAdId: return Qonversion.UserPropertyKey.adjustAdID
        case .advertisingId: return Qonversion.UserPropertyKey.advertisingID
        case .userID: return Qonversion.UserPropertyKey.userID
        case .firebaseAppInstanceId: return Qonversion.UserPropertyKey.firebaseAppInstanceId
        case .appSetId: return Qonversion.UserPropertyKey.appSetId
        case .appMetricaDeviceId: return Qonversion.UserPropertyKey.appMetricaDeviceId
        case .appMetricaUserProfileId: return Qonversion.UserPropertyKey.appMetricaUserProfileId
        case .pushWooshHwId: return Qonversion.UserPropertyKey.pushWooshHwId
        case .pushWooshUserId: return Qonversion.UserPropertyKey.pushWooshUserId
        case .facebookAttribution: return Qonversion.UserPropertyKey.facebookAttribution
        }
    }
}

#Preview {
    NavigationView {
        UserView()
            .environmentObject(AppState())
    }
}
