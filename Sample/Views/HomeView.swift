//
//  HomeView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI

private let clickTimeout: TimeInterval = 0.5
private let requiredClicks = 5

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    
    // Configuration dialog state
    @State private var showConfigurationDialog = false
    @State private var projectKeyInput = ""
    @State private var useCustomUrl = false
    @State private var customUrlInput = ""
    @State private var showRestartAlert = false
    
    // Click tracking state
    @State private var clickCount = 0
    @State private var lastClickTime: Date = .distantPast
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo - tap 5 times to show configuration dialog
                    Image("qonversion_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .padding(.top, 20)
                        .onTapGesture {
                            handleIconTap()
                        }
                    
                    Text("Qonversion SDK Demo")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    // SDK Status
                    VStack(spacing: 8) {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                            Text("SDK Initialized")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // User Info Section
                    if let userInfo = appState.userInfo {
                        UserInfoCard(userInfo: userInfo)
                    }
                    
                    // Quick Actions
                    VStack(spacing: 12) {
                        Text("Quick Actions")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            QuickActionButton(
                                title: "Load Products",
                                icon: "bag.fill",
                                color: .blue
                            ) {
                                Task { await appState.loadProducts() }
                            }
                            
                            QuickActionButton(
                                title: "Check Entitlements",
                                icon: "checkmark.seal.fill",
                                color: .green
                            ) {
                                Task { await appState.loadEntitlements() }
                            }
                            
                            QuickActionButton(
                                title: "Load Offerings",
                                icon: "gift.fill",
                                color: .purple
                            ) {
                                Task { await appState.loadOfferings() }
                            }
                            
                            QuickActionButton(
                                title: "Restore Purchases",
                                icon: "arrow.clockwise",
                                color: .orange
                            ) {
                                Task { await appState.restore() }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Home")
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
            .sheet(isPresented: $showConfigurationDialog) {
                ConfigurationDialogView(
                    projectKeyInput: $projectKeyInput,
                    useCustomUrl: $useCustomUrl,
                    customUrlInput: $customUrlInput,
                    onApply: applyConfiguration,
                    onReset: resetConfiguration,
                    onCancel: { showConfigurationDialog = false }
                )
            }
            .alert("Restart Required", isPresented: $showRestartAlert) {
                Button("Close App") {
                    exit(0)
                }
            } message: {
                Text("The app will be closed. Please reopen it to apply the new configuration.")
            }
        }
    }
    
    // MARK: - Icon Tap Handling
    private func handleIconTap() {
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastClickTime) > clickTimeout {
            resetClickCount()
        }
        
        clickCount += 1
        lastClickTime = currentTime
        
        if clickCount >= requiredClicks {
            showConfigurationDialogWithCurrentValues()
            resetClickCount()
        }
    }
    
    private func resetClickCount() {
        clickCount = 0
        lastClickTime = .distantPast
    }
    
    private func showConfigurationDialogWithCurrentValues() {
        projectKeyInput = ConfigurationManager.getProjectKey()
        if let apiUrl = ConfigurationManager.getApiUrl() {
            useCustomUrl = true
            customUrlInput = apiUrl
        } else {
            useCustomUrl = false
            customUrlInput = ""
        }
        showConfigurationDialog = true
    }
    
    private func applyConfiguration() {
        let apiUrl = useCustomUrl ? customUrlInput : nil
        ConfigurationManager.storeConfiguration(projectKey: projectKeyInput, apiUrl: apiUrl)
        showConfigurationDialog = false
        showRestartAlert = true
    }
    
    private func resetConfiguration() {
        ConfigurationManager.resetConfiguration()
        showConfigurationDialog = false
        showRestartAlert = true
    }
}

// MARK: - User Info Card
struct UserInfoCard: View {
    let userInfo: Qonversion.User
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current User")
                .font(.headline)
            
            InfoRow(label: "Qonversion ID", value: userInfo.qonversionId)
            InfoRow(label: "Identity ID", value: userInfo.identityId ?? "Anonymous")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(12)
        }
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .padding(40)
                .background(Color(.systemGray5))
                .cornerRadius(16)
        }
    }
}

import Qonversion

// MARK: - Configuration Dialog View
struct ConfigurationDialogView: View {
    @Binding var projectKeyInput: String
    @Binding var useCustomUrl: Bool
    @Binding var customUrlInput: String
    
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Project Key")) {
                    TextField("Enter Project Key", text: $projectKeyInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("API Endpoint")) {
                    Picker("Endpoint", selection: $useCustomUrl) {
                        Text("Production (default)").tag(false)
                        Text("Custom URL").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if useCustomUrl {
                        TextField("Enter Custom URL", text: $customUrlInput)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                }
                
                Section(footer: Text("The app will be closed after applying changes. Please reopen it manually.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Reset") {
                        onReset()
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
