//
//  EntitlementsView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct EntitlementsView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    actions
                    streamNote
                    entitlementsList
                    eventsLog

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
            .messageAlerts()
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            ActionButton(title: "Load Entitlements", color: .blue) {
                Task { await appState.loadEntitlements() }
            }

            ActionButton(title: "Restore Purchases", color: .green) {
                Task { await appState.restore() }
            }

            ActionButton(title: "Sync Historical Data", color: .orange) {
                appState.syncHistoricalData()
            }
        }
        .padding(.horizontal)
    }

    /// The old sample had a "set listener" button here. The listener is no
    /// longer something a screen turns on: the SDK exposes async streams that
    /// the app subscribes to once, at launch.
    private var streamNote: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Entitlement updates, deferred purchases and promo intents are observed from launch")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var entitlementsList: some View {
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

                ForEach(appState.entitlements.values.sorted { $0.id < $1.id }, id: \.id) { entitlement in
                    NavigationLink(destination: EntitlementDetailView(entitlement: entitlement)) {
                        EntitlementRow(entitlement: entitlement)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var eventsLog: some View {
        if !appState.sdkEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SDK Events")
                        .font(.headline)
                    Spacer()
                    Button("Clear") { appState.sdkEvents.removeAll() }
                        .font(.caption)
                        .foregroundColor(.red)
                }

                ForEach(Array(appState.sdkEvents.enumerated()), id: \.offset) { index, event in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(event)
                            .font(.caption)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

// MARK: - Entitlement Row

struct EntitlementRow: View {

    let entitlement: Qonversion.Entitlement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entitlement.id)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                StatusBadge(isActive: entitlement.active)
            }

            Text("Product: \(entitlement.productId ?? "N/A")")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Source: \(entitlement.source.rawValue)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Started: \(formatDate(entitlement.startedDate))")
                .font(.caption)
                .foregroundColor(.secondary)

            if let expirationDate: Date = entitlement.expirationDate {
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
}

#Preview {
    EntitlementsView()
        .environmentObject(AppState())
}
