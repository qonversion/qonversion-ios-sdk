//
//  ProductsView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct ProductsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            VStack {
                if appState.products.isEmpty {
                    EmptyStateView(
                        title: "No Products Loaded",
                        subtitle: "Tap the button below to load available products",
                        icon: "bag"
                    )
                } else {
                    List {
                        ForEach(Array(appState.products.values), id: \.qonversionID) { product in
                            NavigationLink(destination: ProductDetailView(product: product)) {
                                ProductRow(product: product)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Products")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await appState.loadProducts() }
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
                if appState.products.isEmpty {
                    await appState.loadProducts()
                }
            }
        }
    }
}

// MARK: - Product Row
struct ProductRow: View {
    let product: Qonversion.Product
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.qonversionID)
                .font(.headline)
            
            HStack {
                Text("Store ID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(product.storeID ?? "N/A")
                    .font(.caption)
            }
            
            HStack {
                Text("Type:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(productTypeString(product.type))
                    .font(.caption)
            }
            
            HStack {
                Text("Price:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(product.prettyPrice)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func productTypeString(_ type: Qonversion.ProductType) -> String {
        switch type {
        case .trial:
            return "Trial"
        case .directSubscription:
            return "Direct Subscription"
        case .oneTime:
            return "One Time"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ProductsView()
        .environmentObject(AppState())
}
