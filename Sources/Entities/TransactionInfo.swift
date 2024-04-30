//
//  TransactionInfo.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 30.04.2024.
//

import Foundation

extension Qonversion {
  
    public struct TransactionInfo: Decodable {
        
        /// Transaction identifier
        let transactionId: String
        
        /// Original transaction identifier.
        let originalTransactionId: String
        
        /// Offer code if it was used.
        let offerCode: String?
        
        /// Transaction date.
        let transactionDate: Date
        
        /// Expiration date if transaction is related to the subscription and it's expired.
        let expirationDate: Date?
        
        /// The date when transaction was revoked. This field represents the time and date the App Store refunded a transaction or revoked it from family sharing.`nil` if the transaction wasn't revoked.
        let transactionRevocationDate: Date?
        
        /// Environment of the transaction
        let environment: Qonversion.Transaction.Environment
        
        /// Type of ownership for the transaction.
        let ownershipType: Qonversion.Transaction.OwnershipType
        
        /// Type of the transaction.
        let type: Qonversion.TransactionInfo.TransactionType
        
        // MARK: Nested structs & enums
        
        /// Type of the transaction.
        enum TransactionType: Decodable {
            
            /// Unknown type
            case unknown
            
            /// Subscription started
            case subscriptionStarted
            
            /// Subscription renewed
            case subscriptionRenewed
            
            /// Trial started
            case trialStarted
            
            /// Intro strated
            case introStarted
            
            /// Intro renewed
            case introRenewed
            
            /// Non-consumable purchase
            case nonConsumablePurchase
        }
        
        enum CodingKeys: CodingKey {
            case transactionId
            case originalTransactionId
            case offerCode
            case transactionDate
            case expirationDate
            case transactionRevocationDate
            case environment
            case ownershipType
            case type
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            transactionId = try container.decode(String.self, forKey: .transactionId)
            originalTransactionId = try container.decode(String.self, forKey: .originalTransactionId)
            offerCode = try container.decode(String.self, forKey: .offerCode)
            transactionDate = try container.decode(Date.self, forKey: .transactionDate)
            expirationDate = try container.decode(Date.self, forKey: .expirationDate)
            transactionRevocationDate = try container.decode(Date.self, forKey: .transactionRevocationDate)
            environment = try container.decode(Qonversion.Transaction.Environment.self, forKey: .environment)
            ownershipType = try container.decode(Qonversion.Transaction.OwnershipType.self, forKey: .ownershipType)
            type = try container.decode(TransactionType.self, forKey: .type)
        }
    }
}
