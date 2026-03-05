//
//  EntitlementsView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct EntitlementsView: View {
    @EnvironmentObject var appState: AppState
    @State private var listenerSet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Action Buttons
                    VStack(spacing: 12) {
                        ActionButton(title: "Load Entitlements", color: .blue) {
                            Task { await appState.loadEntitlements() }
                        }
                        
                        ActionButton(title: "Set Entitlements Listener", color: .purple) {
                            setEntitlementsListener()
                        }
                        
                        ActionButton(title: "Restore Purchases", color: .green) {
                            Task { await appState.restore() }
                        }
                        
                        ActionButton(title: "Sync Historical Data", color: .orange) {
                            appState.syncHistoricalData()
                        }
                        
                        ActionButton(title: "Sync StoreKit 2 Purchases", color: .pink) {
                            appState.syncStoreKit2Purchases()
                        }
                    }
                    .padding(.horizontal)
                    
                    // Listener Status
                    if listenerSet {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Entitlements listener is active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    // Entitlements List
                    if appState.entitlements.isEmpty {
                        EmptyStateView(
                            title: "No Entitlements",
                            subtitle: "Tap 'Load Entitlements' to fetch your current entitlements",
                            icon: "checkmark.seal"
                        )
                        .frame(height: 200)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Entitlements")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(Array(appState.entitlements.values), id: \.entitlementID) { entitlement in
                                NavigationLink(destination: EntitlementDetailView(entitlement: entitlement)) {
                                    EntitlementRow(entitlement: entitlement)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Entitlements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await appState.loadEntitlements() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
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
    }
    
    private func setEntitlementsListener() {
        Qonversion.shared().setEntitlementsUpdateListener(EntitlementsListenerHandler.shared)
        EntitlementsListenerHandler.shared.appState = appState
        listenerSet = true
        appState.successMessage = "Entitlements listener set successfully!"
    }
}

// MARK: - Entitlements Listener Handler
class EntitlementsListenerHandler: NSObject, Qonversion.EntitlementsUpdateListener {
    static let shared = EntitlementsListenerHandler()
    weak var appState: AppState?
    
    func didReceiveUpdatedEntitlements(_ entitlements: [String: Qonversion.Entitlement]) {
        Task { @MainActor in
            appState?.entitlements = entitlements
        }
    }

    func didReceiveUpdatedEntitlements(_ entitlements: [String: Qonversion.Entitlement], purchaseResult: Qonversion.PurchaseResult?) {
        Task { @MainActor in
            appState?.entitlements = entitlements
            if let purchaseResult, purchaseResult.isSuccessful, entitlements.isEmpty {
                appState?.successMessage = "Consumable purchase completed in background"
            }
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(color)
                .cornerRadius(10)
        }
    }
}

// MARK: - Entitlement Row
struct EntitlementRow: View {
    let entitlement: Qonversion.Entitlement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entitlement.entitlementID)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                StatusBadge(isActive: entitlement.isActive)
            }
            
            Text("Product: \(entitlement.productID)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Started: \(formatDate(entitlement.startedDate))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let expirationDate = entitlement.expirationDate {
                Text("Expires: \(formatDate(expirationDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let isActive: Bool
    
    var body: some View {
        Text(isActive ? "Active" : "Inactive")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.green : Color.red)
            .cornerRadius(8)
    }
}

#Preview {
    EntitlementsView()
        .environmentObject(AppState())
}
