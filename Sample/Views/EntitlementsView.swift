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
                        
                        ActionButton(title: "Set Deferred Purchases Listener", color: .purple) {
                            setDeferredPurchasesListener()
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
                            Text("Deferred purchases listener is active")
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
    
    private func setDeferredPurchasesListener() {
        Qonversion.shared().setDeferredPurchasesListener(DeferredPurchasesListenerHandler.shared)
        DeferredPurchasesListenerHandler.shared.appState = appState
        listenerSet = true
        appState.successMessage = "Deferred purchases listener set successfully!"
    }
}

// MARK: - Deferred Purchases Listener Handler
class DeferredPurchasesListenerHandler: NSObject, Qonversion.DeferredPurchasesListener {
    static let shared = DeferredPurchasesListenerHandler()
    weak var appState: AppState?

    func deferredPurchaseCompleted(_ purchaseResult: Qonversion.PurchaseResult) {
        Task { @MainActor in
            if purchaseResult.isSuccessful, let entitlements = purchaseResult.entitlements {
                for (key, value) in entitlements {
                    appState?.entitlements[key] = value
                }
                appState?.successMessage = "Deferred purchase completed successfully!"
            } else if purchaseResult.isError {
                appState?.errorMessage = purchaseResult.error?.localizedDescription ?? "Deferred purchase failed"
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
