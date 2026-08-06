//
//  ProductDetailView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct ProductDetailView: View {

    @EnvironmentObject var appState: AppState
    let product: Qonversion.Product

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                DetailSection(title: "Basic Information") {
                    DetailRow(label: "Qonversion ID", value: product.qonversionId)
                    DetailRow(label: "Store ID", value: product.storeId)
                    DetailRow(label: "Type", value: productTypeString(product.type))
                    DetailRow(label: "Store product linked", value: product.isStoreProductLinked ? "Yes" : "No")
                }

                // Everything below comes from StoreKit, so it is empty until
                // the store product is linked — which is exactly what a
                // misconfigured product in the dashboard looks like.
                if product.isStoreProductLinked {
                    DetailSection(title: "Pricing") {
                        DetailRow(label: "Display Price", value: product.displayPrice ?? "N/A")
                        DetailRow(label: "Price", value: product.price.map { "\($0)" } ?? "N/A")
                    }

                    DetailSection(title: "Store Information") {
                        DetailRow(label: "Title", value: product.displayName ?? "N/A")
                        DetailRow(label: "Description", value: product.description ?? "N/A")
                        DetailRow(label: "Family Shareable", value: product.isFamilyShareable.map { $0 ? "Yes" : "No" } ?? "N/A")
                    }

                    subscriptionSection
                } else {
                    Text("This product is not linked to a store product. Prices, titles and subscription details come from StoreKit and stay empty until it is.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                purchaseButton

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
        .messageAlerts()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(product.displayName ?? product.qonversionId)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(product.displayPrice ?? "—")
                .font(.title2)
                .foregroundColor(.green)
        }
        .padding()
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        if let subscription: Qonversion.Product.SubscriptionInfo = product.subscription {
            DetailSection(title: "Subscription Details") {
                DetailRow(label: "Duration", value: formatSubscriptionPeriod(subscription.subscriptionPeriod))
                DetailRow(label: "Subscription Group", value: subscription.subscriptionGroupId)
                DetailRow(label: "Promotional Offers", value: "\(subscription.promotionalOffers.count)")
                DetailRow(label: "Win-back Offers", value: "\(subscription.winBackOffers.count)")
            }

            // The trial is an offer now, not a separate period on the product.
            if let intro: Qonversion.Product.SubscriptionOffer = subscription.introductoryOffer {
                DetailSection(title: "Introductory Offer") {
                    DetailRow(label: "Duration", value: formatSubscriptionPeriod(intro.period))
                    DetailRow(label: "Periods", value: "\(intro.periodCount)")
                    DetailRow(label: "Price", value: intro.displayPrice)
                }
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await appState.purchase(product) }
        } label: {
            Text("Purchase Product")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(product.isStoreProductLinked ? Color.blue : Color.gray)
                .cornerRadius(12)
        }
        .disabled(!product.isStoreProductLinked)
        .padding(.horizontal)
        .padding(.top, 20)
    }

    private func formatSubscriptionPeriod(_ period: Qonversion.Product.SubscriptionPeriod?) -> String {
        guard let period: Qonversion.Product.SubscriptionPeriod = period else { return "N/A" }

        let unitString: String
        switch period.unit {
        case .day:
            unitString = period.value == 1 ? "day" : "days"
        case .week:
            unitString = period.value == 1 ? "week" : "weeks"
        case .month:
            unitString = period.value == 1 ? "month" : "months"
        case .year:
            unitString = period.value == 1 ? "year" : "years"
        case .unknown:
            unitString = "period"
        }

        return "\(period.value) \(unitString)"
    }
}

#Preview {
    Text("Product detail requires a loaded product")
}
