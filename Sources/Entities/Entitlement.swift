//
//  Entitlement.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 26.04.2024.
//

import Foundation

extension Qonversion {

    public struct Entitlement: Decodable {
        
        /// Qonversion entitlement identifier.
        let id: String
        
        /// Identifier of the product that grants current entitlement.
        let productId: String
        
        /// Use for checking entitlement for current user.
        /// Pay attention, active == true not mean that the subscription is renewable.
        /// Subscription could be canceled, but the user still has an entitlement.
        let active: Bool
     
        /// A renew state of the current entitlement.
        let renewState: Qonversion.Entitlement.RenewState
        
        /// Source of the purchase via which the entitlement was activated.
        let source: Qonversion.Entitlement.Source
        
        /// Date when the entitlement occurs initially.
        let startedDate: Date
        
        /// Expiration date for entitlements that was granted via subscriptions or manually. `nil` for other cases.
        let expirationDate: Date?
        
        /// Renews count for the entitlement. Renews count starts from the second paid subscription.
        /// For example, we have 20 transactions. One is the trial, and one is the first paid transaction after the trial.
        /// Renews count is equal to 18.
        let renewsCount: Int
        
        /// Date when the trial was activated or `nil` if there is no trial for the subscription that unlocked the current entitlement or it's not a subscription.
        let trialStartDate: Date?
        
        /// Date of the first paid transaction that unlocked the current entitlement.
        let firstPurchaseDate: Date?
        
        /// Date of the last paid transaction that unlocked the current entitlement.
        let lastPurchaseDate: Date?
        
        /// Last activaed offer code.
        let lastActivatedOfferCode: String?
        
        /// Grant type for the entitlement
        let grantType: Qonversion.Entitlement.GrantType
        
        /// Date when the auto-renew was disabled for the subscription that grants the current entitlement. `nil` if it's not disabled or the entitlement is not granted via a subscription.
        let autoRenewDisableDate: Date?
        
        /// Array of the transactions that unlocked current entitlement.
        let transactions: [Qonversion.TransactionInfo]
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            productId = try container.decode(String.self, forKey: .productId)
            active = try container.decode(Bool.self, forKey: .active)
            renewState = try container.decode(RenewState.self, forKey: .renewState)
            source = try container.decode(Source.self, forKey: .source)
            startedDate = try container.decode(Date.self, forKey: .startedDate)
            expirationDate = try container.decode(Date.self, forKey: .expirationDate)
            renewsCount = try container.decode(Int.self, forKey: .renewsCount)
            trialStartDate = try container.decode(Date.self, forKey: .trialStartDate)
            firstPurchaseDate = try container.decode(Date.self, forKey: .firstPurchaseDate)
            lastPurchaseDate = try container.decode(Date.self, forKey: .lastPurchaseDate)
            lastActivatedOfferCode = try container.decode(String.self, forKey: .lastActivatedOfferCode)
            grantType = try container.decode(GrantType.self, forKey: .grantType)
            autoRenewDisableDate = try container.decode(Date.self, forKey: .autoRenewDisableDate)
            transactions = try container.decode([TransactionInfo].self, forKey: .transactions)            
        }
        
        // MARK: - Nested structs & enums
        
        public enum RenewState: Decodable {
            #warning("Update here after product requirements discuss")
            case unknown
        }
        
        public enum Source: Decodable {
            
            /// Unknown source
            case unknown
            
            /// Source of the entitlement is App Store.
            case appStore
            
            /// Source of the entitlement is Android Play Store.
            case playStore
            
            /// Source of the entitlement is Stripe.
            case stripe
            
            /// Entitlement was granted manually via Qonversion dashboard or API.
            case manual
        }
        
        /// Grant type for the entitlement.
        public enum GrantType: Decodable {
            
            /// Entitlement was granted via purchase.
            case purchase
            
            /// Entitlement was granted via family sharing.
            case familySharing
            
            /// Entitlement was granted via offer code.
            case offerCode
            
            /// Entitlement was granted manually via Qonversion dashboard or API.
            case manual
        }
        
        // MARK: - Private
        
        private enum CodingKeys: String, CodingKey {
            case id, productId, active, renewState, source, startedDate, expirationDate, renewsCount, trialStartDate, firstPurchaseDate, lastPurchaseDate, lastActivatedOfferCode, grantType, autoRenewDisableDate, transactions
        }
    }
}
