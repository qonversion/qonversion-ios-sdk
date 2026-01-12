//
//  OfferingsView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct OfferingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let offerings = appState.offerings {
                        // Main Offering Info
                        if let mainOffering = offerings.main {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Main Offering")
                                        .font(.headline)
                                    Spacer()
                                    Text(mainOffering.identifier)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Available Offerings
                        ForEach(offerings.availableOfferings, id: \.identifier) { offering in
                            OfferingCard(offering: offering)
                        }
                    } else {
                        EmptyStateView(
                            title: "No Offerings Loaded",
                            subtitle: "Tap the button above to load available offerings",
                            icon: "gift"
                        )
                        .frame(height: 300)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Offerings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await appState.loadOfferings() }
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
            .task {
                if appState.offerings == nil {
                    await appState.loadOfferings()
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

// MARK: - Offering Card
struct OfferingCard: View {
    @EnvironmentObject var appState: AppState
    let offering: Qonversion.Offering
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(offering.identifier)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("Tag:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(tagString(offering.tag))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                Divider()
                
                if offering.products.isEmpty {
                    Text("No products in this offering")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    VStack(spacing: 8) {
                        ForEach(offering.products, id: \.qonversionID) { product in
                            OfferingProductRow(product: product)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func tagString(_ tag: Qonversion.OfferingTag) -> String {
        switch tag {
        case .none:
            return "None"
        case .main:
            return "Main"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Offering Product Row
struct OfferingProductRow: View {
    @EnvironmentObject var appState: AppState
    let product: Qonversion.Product
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.skProduct?.localizedTitle ?? product.qonversionID)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let description = product.skProduct?.localizedDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Button {
                Task { await appState.purchase(product) }
            } label: {
                Text(product.prettyPrice ?? "N/A")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    OfferingsView()
        .environmentObject(AppState())
}
