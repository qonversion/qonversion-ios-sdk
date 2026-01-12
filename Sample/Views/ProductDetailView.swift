//
//  ProductDetailView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct ProductDetailView: View {
    @EnvironmentObject var appState: AppState
    let product: Qonversion.Product
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text(product.skProduct?.localizedTitle ?? product.qonversionID)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(product.prettyPrice)
                        .font(.title2)
                        .foregroundColor(.green)
                }
                .padding()
                
                // Basic Information
                DetailSection(title: "Basic Information") {
                    DetailRow(label: "Qonversion ID", value: product.qonversionID)
                    DetailRow(label: "Store ID", value: product.storeID)
                    DetailRow(label: "Type", value: productTypeString(product.type))
                    DetailRow(label: "Offering ID", value: product.offeringID ?? "N/A")
                }
                
                // Pricing
                DetailSection(title: "Pricing") {
                    DetailRow(label: "Pretty Price", value: product.prettyPrice ?? "N/A")
                    if let skProduct = product.skProduct {
                        DetailRow(label: "Price", value: "\(skProduct.price)")
                        DetailRow(label: "Currency", value: skProduct.priceLocale.currencyCode ?? "N/A")
                    }
                }
                
                // Store Information
                if let skProduct = product.skProduct {
                    DetailSection(title: "Store Information") {
                        DetailRow(label: "Title", value: skProduct.localizedTitle)
                        DetailRow(label: "Description", value: skProduct.localizedDescription)
                    }
                }
                
                // Subscription Details
                DetailSection(title: "Subscription Details") {
                    if let period = product.subscriptionPeriod {
                        DetailRow(label: "Duration", value: formatSubscriptionPeriod(period))
                    }
                    if let trialPeriod = product.trialPeriod {
                        DetailRow(label: "Trial Duration", value: formatSubscriptionPeriod(trialPeriod))
                    }
                }
                
                // Purchase Button
                Button {
                    Task { await appState.purchase(product) }
                } label: {
                    Text("Purchase Product")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .navigationTitle("Product Details")
        .navigationBarTitleDisplayMode(.inline)
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
    
    private func formatSubscriptionPeriod(_ period: Qonversion.SubscriptionPeriod) -> String {
        let unitString: String
        switch period.unit {
        case .day:
            unitString = period.unitCount == 1 ? "day" : "days"
        case .week:
            unitString = period.unitCount == 1 ? "week" : "weeks"
        case .month:
            unitString = period.unitCount == 1 ? "month" : "months"
        case .year:
            unitString = period.unitCount == 1 ? "year" : "years"
        @unknown default:
            unitString = "period"
        }
        return "\(period.unitCount) \(unitString)"
    }
}

// MARK: - Detail Section
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                content
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        ProductDetailView(product: Qonversion.Product())
            .environmentObject(AppState())
    }
}
