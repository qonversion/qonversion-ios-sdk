//
//  HomeView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    Image("qonversion_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .padding(.top, 20)
                    
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
        }
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

#Preview {
    HomeView()
        .environmentObject(AppState())
}
