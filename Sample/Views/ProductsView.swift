//
//  ProductsView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
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
                        subtitle: "Pull to refresh, or tap the button in the toolbar",
                        icon: "bag"
                    )
                } else {
                    List {
                        Section {
                            ForEach(appState.products, id: \.qonversionId) { product in
                                NavigationLink(destination: ProductDetailView(product: product)) {
                                    ProductRow(
                                        product: product,
                                        eligibility: appState.introEligibility[product.qonversionId]
                                    )
                                }
                            }
                        } footer: {
                            Text("The catalog is cached for a minute. A refresh inside that window is served from memory without a request.")
                        }

                        Section {
                            Button("Check Trial / Intro Eligibility") {
                                Task { await appState.loadIntroEligibility() }
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
            .messageAlerts()
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
    let eligibility: Qonversion.IntroEligibilityStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.qonversionId)
                .font(.headline)

            LabeledCaption(label: "Store ID", value: product.storeId)
            LabeledCaption(label: "Type", value: productTypeString(product.type))

            HStack {
                Text("Price:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                // nil until the store product is linked: the Qonversion catalog
                // knows the identifiers, StoreKit owns the price.
                Text(product.displayPrice ?? "Not linked to a store product")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(product.displayPrice == nil ? .secondary : .green)
            }

            if let eligibility: Qonversion.IntroEligibilityStatus = eligibility {
                LabeledCaption(label: "Intro eligibility", value: introEligibilityString(eligibility))
            }
        }
        .padding(.vertical, 4)
    }
}

struct LabeledCaption: View {

    let label: String
    let value: String

    var body: some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Formatting

func productTypeString(_ type: Qonversion.Product.ProductType?) -> String {
    guard let type: Qonversion.Product.ProductType = type else { return "Unknown" }

    switch type {
    case .consumable:
        return "Consumable"
    case .nonConsumable:
        return "Non-Consumable"
    case .nonRenewable:
        return "Non-Renewing Subscription"
    case .autoRenewable:
        return "Auto-Renewable Subscription"
    }
}

func introEligibilityString(_ status: Qonversion.IntroEligibilityStatus) -> String {
    switch status {
    case .unknown:
        return "Unknown"
    case .nonIntroOrTrialProduct:
        return "No intro or trial"
    case .eligible:
        return "Eligible"
    case .ineligible:
        return "Already used"
    }
}

#Preview {
    ProductsView()
        .environmentObject(AppState())
}
