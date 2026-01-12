//
//  EntitlementDetailView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct EntitlementDetailView: View {
    let entitlement: Qonversion.Entitlement
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text(entitlement.entitlementID)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    StatusBadge(isActive: entitlement.isActive)
                }
                .padding()
                
                // Basic Information
                DetailSection(title: "Basic Information") {
                    DetailRow(label: "ID", value: entitlement.entitlementID)
                    DetailRow(label: "Product ID", value: entitlement.productID)
                    DetailRow(label: "Renew State", value: renewStateString(entitlement.renewState))
                    DetailRow(label: "Source", value: sourceString(entitlement.source))
                    DetailRow(label: "Grant Type", value: grantTypeString(entitlement.grantType))
                    DetailRow(label: "Renews Count", value: "\(entitlement.renewsCount)")
                }
                
                // Dates
                DetailSection(title: "Dates") {
                    DetailRow(label: "Started Date", value: formatDate(entitlement.startedDate))
                    if let expirationDate = entitlement.expirationDate {
                        DetailRow(label: "Expiration Date", value: formatDate(expirationDate))
                    }
                    if let trialStartDate = entitlement.trialStartDate {
                        DetailRow(label: "Trial Start Date", value: formatDate(trialStartDate))
                    }
                    if let firstPurchaseDate = entitlement.firstPurchaseDate {
                        DetailRow(label: "First Purchase Date", value: formatDate(firstPurchaseDate))
                    }
                    if let lastPurchaseDate = entitlement.lastPurchaseDate {
                        DetailRow(label: "Last Purchase Date", value: formatDate(lastPurchaseDate))
                    }
                    if let autoRenewDisableDate = entitlement.autoRenewDisableDate {
                        DetailRow(label: "Auto Renew Disable Date", value: formatDate(autoRenewDisableDate))
                    }
                }
                
                // Additional Information
                DetailSection(title: "Additional Information") {
                    if let lastActivatedOfferCode = entitlement.lastActivatedOfferCode {
                        DetailRow(label: "Last Activated Offer Code", value: lastActivatedOfferCode)
                    }
                    DetailRow(label: "Transactions", value: "\(entitlement.transactions.count) transaction(s)")
                }
                
                // Transactions
                if !entitlement.transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transactions")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(entitlement.transactions, id: \.originalTransactionId) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
                
                Spacer()
            }
        }
        .navigationTitle("Entitlement Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func renewStateString(_ state: Qonversion.EntitlementRenewState) -> String {
        switch state {
        case .nonRenewable:
            return "Non Renewable"
        case .willRenew:
            return "Will Renew"
        case .cancelled:
            return "Cancelled"
        case .billingIssue:
            return "Billing Issue"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
    
    private func sourceString(_ source: Qonversion.EntitlementSource) -> String {
        switch source {
        case .appStore:
            return "App Store"
        case .playStore:
            return "Play Store"
        case .stripe:
            return "Stripe"
        case .manual:
            return "Manual"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
    
    private func grantTypeString(_ grantType: Qonversion.EntitlementGrantType) -> String {
        switch grantType {
        case .purchase:
            return "Purchase"
        case .familySharing:
            return "Family Sharing"
        case .offerCode:
            return "Offer Code"
        case .manual:
            return "Manual"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Transaction Row
struct TransactionRow: View {
    let transaction: Qonversion.Transaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transaction")
                .font(.subheadline)
                .fontWeight(.medium)
            
            DetailRow(label: "Original Transaction ID", value: transaction.originalTransactionId)
            DetailRow(label: "Transaction ID", value: transaction.transactionId)
            DetailRow(label: "Environment", value: environmentString(transaction.environment))
            
            DetailRow(label: "Transaction Date", value: formatDate(transaction.transactionDate))
            if let expirationDate = transaction.expirationDate {
                DetailRow(label: "Expiration Date", value: formatDate(expirationDate))
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
    
    private func environmentString(_ env: Qonversion.TransactionEnvironment) -> String {
        switch env {
        case .production:
            return "Production"
        case .sandbox:
            return "Sandbox"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    NavigationView {
        EntitlementDetailView(entitlement: Qonversion.Entitlement())
            .environmentObject(AppState())
    }
}
