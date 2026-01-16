//
//  OtherView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct OtherView: View {
    @EnvironmentObject var appState: AppState
    @State private var fallbackAccessible: Bool?
    @State private var promoDelegateSet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Fallback File Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fallback File")
                        .font(.headline)
                    
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
                        checkFallbackFile()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // iOS-Only Methods Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("iOS-Only Methods")
                        .font(.headline)
                    
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
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Promo Purchases Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Promo Purchases")
                        .font(.headline)
                    
                    if promoDelegateSet {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Promo purchases delegate is active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ActionButton(title: "Set Promo Purchases Delegate", color: .pink) {
                        Qonversion.shared().setPromoPurchasesDelegate(PromoPurchasesHandler.shared)
                        promoDelegateSet = true
                        appState.successMessage = "Promo purchases delegate set!"
                    }
                    .disabled(promoDelegateSet)
                    
                    Text("Note: Promo purchases delegate is already set during SDK initialization")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
            }
            .padding()
        }
        .navigationTitle("Other")
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
    
    private var fallbackStatusColor: Color {
        switch fallbackAccessible {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .gray
        }
    }
    
    private var fallbackStatusText: String {
        switch fallbackAccessible {
        case .some(true): return "Accessible"
        case .some(false): return "Not Accessible"
        case .none: return "Not Checked"
        }
    }
    
    private func checkFallbackFile() {
        let accessible = Qonversion.shared().isFallbackFileAccessible()
        fallbackAccessible = accessible
        appState.successMessage = "Fallback file accessible: \(accessible)"
    }
}

#Preview {
    NavigationView {
        OtherView()
            .environmentObject(AppState())
    }
}
