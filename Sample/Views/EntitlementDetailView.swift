//
//  EntitlementDetailView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct EntitlementDetailView: View {

    let entitlement: Qonversion.Entitlement

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(entitlement.id)
                        .font(.title)
                        .fontWeight(.bold)

                    StatusBadge(isActive: entitlement.active)
                }
                .padding()

                // Every one of these enums is string-backed on the wire, so the
                // raw value IS the backend's own vocabulary — worth showing
                // verbatim when checking what the API returned.
                DetailSection(title: "Basic Information") {
                    DetailRow(label: "ID", value: entitlement.id)
                    DetailRow(label: "Product ID", value: entitlement.productId ?? "N/A")
                    DetailRow(label: "Renew State", value: entitlement.renewState.rawValue)
                    DetailRow(label: "Source", value: entitlement.source.rawValue)
                    DetailRow(label: "Grant Type", value: entitlement.grantType.rawValue)
                    DetailRow(label: "Renews Count", value: "\(entitlement.renewsCount)")
                }

                DetailSection(title: "Dates") {
                    DetailRow(label: "Started Date", value: formatDate(entitlement.startedDate))
                    DetailRow(label: "Expiration Date", value: formatDate(entitlement.expirationDate))
                    if let trialStartDate: Date = entitlement.trialStartDate {
                        DetailRow(label: "Trial Start Date", value: formatDate(trialStartDate))
                    }
                    if let firstPurchaseDate: Date = entitlement.firstPurchaseDate {
                        DetailRow(label: "First Purchase Date", value: formatDate(firstPurchaseDate))
                    }
                    if let lastPurchaseDate: Date = entitlement.lastPurchaseDate {
                        DetailRow(label: "Last Purchase Date", value: formatDate(lastPurchaseDate))
                    }
                    if let autoRenewDisableDate: Date = entitlement.autoRenewDisableDate {
                        DetailRow(label: "Auto Renew Disable Date", value: formatDate(autoRenewDisableDate))
                    }
                }

                DetailSection(title: "Additional Information") {
                    if let lastActivatedOfferCode: String = entitlement.lastActivatedOfferCode {
                        DetailRow(label: "Last Activated Offer Code", value: lastActivatedOfferCode)
                    }
                    DetailRow(label: "Transactions", value: "\(entitlement.transactions.count) transaction(s)")
                }

                if !entitlement.transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transactions")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(Array(entitlement.transactions.enumerated()), id: \.offset) { _, transaction in
                            StoreTransactionRow(transaction: transaction)
                        }
                    }
                }

                Spacer()
            }
        }
        .navigationTitle("Entitlement Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Store Transaction Row

/// The billing-history record as the Qonversion backend knows it — not the
/// StoreKit object.
struct StoreTransactionRow: View {

    let transaction: Qonversion.Entitlement.StoreTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transaction")
                .font(.subheadline)
                .fontWeight(.medium)

            DetailRow(label: "Original Transaction ID", value: transaction.originalTransactionId ?? "N/A")
            DetailRow(label: "Transaction ID", value: transaction.transactionId ?? "N/A")
            DetailRow(label: "Environment", value: transaction.environment.rawValue)
            DetailRow(label: "Ownership", value: transaction.ownershipType.rawValue)
            DetailRow(label: "Type", value: transaction.type.rawValue)
            DetailRow(label: "Transaction Date", value: formatDate(transaction.transactionDate))
            DetailRow(label: "Expiration Date", value: formatDate(transaction.expirationDate))
            if let revocationDate: Date = transaction.revocationDate {
                DetailRow(label: "Revoked", value: formatDate(revocationDate))
            }
            if let offerCode: String = transaction.offerCode {
                DetailRow(label: "Offer Code", value: offerCode)
            }
            if let promoOfferId: String = transaction.promoOfferId {
                DetailRow(label: "Promo Offer ID", value: promoOfferId)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    Text("Entitlement detail requires a loaded entitlement")
}
