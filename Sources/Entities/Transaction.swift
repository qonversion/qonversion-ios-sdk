//
//  Transaction.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 01.03.2024.
//

import Foundation
import StoreKit

extension Qonversion {

    /// StoreKit [Transaction](https://developer.apple.com/documentation/storekit/transaction) wrapper.
    public struct Transaction {
        
        /// The raw JSON representation of the transaction information.
        public var jsonRepresentation: Data?

        /// The unique identifier for the transaction.
        public let id: String?

        /// The original transaction identifier of a purchase.
        public let originalId: String?

        /// A unique ID that identifies subscription purchase events across devices, including subscription renewals.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var webOrderLineItemId: String? { storeKitTransaction?.webOrderLineItemID }

        /// The product identifier of the in-app purchase.
        public let productId: String

        /// The identifier of the subscription group that the subscription belongs to.
        public let subscriptionGroupId: String?
        
        /// The bundle identifier for the app.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var appBundleId: String? { storeKitTransaction?.appBundleID }

        /// The date that the App Store charged the user’s account for a purchased or restored product, or for a subscription purchase or renewal after a lapse.
        public let purchaseDate: Date?

        /// The date of purchase for the original transaction.
        public let originalPurchaseDate: Date?

        /// The date the subscription expires or renews.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var expirationDate: Date? { storeKitTransaction?.expirationDate }

        /// The number of consumable products purchased.
        public let purchasedQuantity: Int

        /// A Boolean that indicates whether the user upgraded to another subscription.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var isUpgraded: Bool? { storeKitTransaction?.isUpgraded }
        
        /// The subscription offer that applies to the transaction, including its offer type, payment mode, and ID.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var offer: Qonversion.Transaction.Offer? { _offer }
        
        /// The reason that the App Store refunded the transaction or revoked it from Family Sharing.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var revocationReason: Qonversion.Transaction.RevocationReason? { Qonversion.Transaction.RevocationReason.from(revocataionReason: storeKitTransaction?.revocationReason) }
        
        /// The date that the App Store refunded the transaction or revoked it from Family Sharing.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var revocationDate: Date? { storeKitTransaction?.revocationDate }
        
        /// A UUID that associates the transaction with a user on your own service.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var appAccountToken: UUID? { storeKitTransaction?.appAccountToken }
        
        /// The Apple server environment that generates and signs the transaction.
        @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
        public var environment: Qonversion.Transaction.Environment? { Qonversion.Transaction.Environment(rawValue: storeKitTransaction?.environment.rawValue ?? "") }
        
        /// A cause of a purchase transaction, indicating whether it’s a customer’s purchase or an auto-renewable subscription renewal that the system initiates.
        @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
        public var reason: Qonversion.Transaction.Reason {
            guard let storeKitTransaction = storeKitTransaction,
                  let reason = Qonversion.Transaction.Reason(rawValue: storeKitTransaction.reason.rawValue)
            else { return Qonversion.Transaction.Reason.purchase }
            
            return reason
        }
        
        /// The decimal representation of the cost of the product, in local currency.
        public let price: Decimal?
        
        /// Transaction currency info.
        public let currency: Qonversion.Currency?
        
        /// Transaction storefront info.
        public let storefront: Qonversion.Storefront?
        
        /// The device verification value to use to verify whether the renewal information belongs to the device.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var deviceVerification: Data? { storeKitTransaction?.deviceVerification }
        
        /// The UUID to use to compute the device verification value.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var deviceVerificationNonce: UUID? { storeKitTransaction?.deviceVerificationNonce }
        
        /// The date that the App Store signed the JWS renewal information.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var signedDate: Date? { storeKitTransaction?.signedDate }
        
        /// A value that indicates whether the transaction was purchased by the user, or is made available to them through Family Sharing.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var ownershipType: Qonversion.Transaction.OwnershipType {
            guard let storeKitTransaction = storeKitTransaction,
                  let ownershipType = Qonversion.Transaction.OwnershipType(rawValue: storeKitTransaction.ownershipType.rawValue)
            else { return Qonversion.Transaction.OwnershipType.purchased }
            
            return ownershipType
        }
        
        /// Original StoreKit 2 Transaction.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var storeKitTransaction: StoreKit.Transaction? { _storeKitTransaction as? StoreKit.Transaction }
        
        /// Original old StoreKit Transaction
        public let skPaymentTransaction: SKPaymentTransaction?
        
        // MARK: - Nested structures and enums
        
        /// Enum describes possible reasons of transaction's revocation.
        /// This enum is a wrapper of StoreKit Transaction's [RevocationReason](https://developer.apple.com/documentation/storekit/transaction/revocationreason)
        public enum RevocationReason {
            
            /// The user refunded the transaction due to an issue in your app.
            case developerIssue
            
            /// The transaction was revoked for some other reason.
            case other
            
            @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
            static func from(revocataionReason: StoreKit.Transaction.RevocationReason?) -> Qonversion.Transaction.RevocationReason? {
                guard let reason: StoreKit.Transaction.RevocationReason = revocataionReason else { return nil }
                
                switch reason {
                case .developerIssue:
                    return .developerIssue
                default:
                    return .other
                }
            }
            
        }
        
        /// Transaction ownership type.
        /// StoreKit [OwnershipType](https://developer.apple.com/documentation/storekit/transaction/ownershiptype) wrapper
        public enum OwnershipType: String {
            
            /// The current user is the purchaser of the transaction.
            case purchased
            
            /// The user has access to this transaction through family sharing.
            case familyShared
            
        }
        
        /// Transaction environment type.
        /// App Store [Environment](https://developer.apple.com/documentation/storekit/appstore/environment) wrapper.
        public enum Environment: String {
            
            /// A value that indicates the production server environment.
            case production
            
            /// A value that indicates the sandbox server environment.
            case sandbox
            
            /// A value that indicates the StoreKit Testing in Xcode environment.
            case xcode
            
        }
        
        /// The subscription offers that apply to a transaction.
        public struct Offer {
            
            /// A string that identifies the subscription offer that applies to the transaction.
            public let id: String?
            
            /// The type of subscription offer that applies to the transaction.
            public let type: Transaction.Offer.OfferType?
            
            /// The payment modes for subscription offers that apply to a transaction.
            @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
            public var paymentMode: Qonversion.Transaction.Offer.PaymentMode? {
                guard let offer = _offer as? StoreKit.Transaction.Offer else { return nil }
                return Qonversion.Transaction.Offer.PaymentMode.from(paymentMode: offer.paymentMode)
            }
            
            /// Original object of StoreKit Transaction [Offer](https://developer.apple.com/documentation/storekit/transaction/offer)
            @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
            public var originalOffer: StoreKit.Transaction.Offer? { _offer as? StoreKit.Transaction.Offer }
            
            // Workaround to make originalOffer variable available for specific OS versions
            let _offer: Any?
            
            @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
            init?(with transaction: StoreKit.Transaction) {
                self.type = Qonversion.Transaction.Offer.OfferType.from(transaction: transaction)
                
                if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *) {
                    guard let offer = transaction.offer else { return nil }
                    
                    self._offer = offer
                    self.id = offer.id
                } else {
                    self.id = transaction.offerID
                    self._offer = nil
                }
            }
            
            // MARK: Nested stucts & enums
            
            /// The types of offers for auto-renewable subscriptions.
            public enum OfferType: String {
                
                /// An introductory offer for an auto-renewable subscription.
                case introductory
                
                /// A promotional offer for an auto-renewable subscription.
                case promotional
                
                /// An offer with a subscription offer code, for an auto-renewable subscription.
                case code
                
                @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
                static func from(transaction: StoreKit.Transaction?) -> Qonversion.Transaction.Offer.OfferType? {
                    guard let transaction: StoreKit.Transaction = transaction else { return nil }
                   
                    let type: StoreKit.Transaction.OfferType?
                    if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *) {
                        type = transaction.offer?.type
                    } else {
                        type = transaction.offerType
                    }
                    
                    guard let type: StoreKit.Transaction.OfferType = type else { return nil }
                    
                    switch type {
                    case .introductory:
                        return Qonversion.Transaction.Offer.OfferType.introductory
                    case .promotional:
                        return Qonversion.Transaction.Offer.OfferType.promotional
                    case .code:
                        return Qonversion.Transaction.Offer.OfferType.code
                    default:
                        return nil
                    }
                }
            }
            
            /// The payment modes for subscription offers that apply to a transaction.
            public enum PaymentMode: String {
                
                /// A payment mode of a product discount that indicates a free trial.
                case freeTrial
                
                /// A payment mode of a product discount that’s billed over a single or multiple billing periods.
                case payAsYouGo
                
                /// A payment mode of a product discount that’s paid up front.
                case payUpFront
                
                @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
                static func from(paymentMode: StoreKit.Transaction.Offer.PaymentMode?) -> Qonversion.Transaction.Offer.PaymentMode? {
                    guard let paymentMode = paymentMode else { return nil }
                    switch paymentMode {
                    case .freeTrial:
                        return Qonversion.Transaction.Offer.PaymentMode.freeTrial
                    case .payAsYouGo:
                        return Qonversion.Transaction.Offer.PaymentMode.payAsYouGo
                    case .payUpFront:
                        return Qonversion.Transaction.Offer.PaymentMode.payUpFront
                    default:
                        return nil
                    }
                }
            }
        }
        
        /// A cause of a purchase transaction, indicating whether it’s a customer’s purchase or an auto-renewable subscription renewal that the system initiates.
        public enum Reason: String {
            
            /// A transaction reason that indicates a purchase is initiated by a customer.
            case purchase
            
            /// A transaction reason that indicates the App Store server initiated a purchase transaction to renew an auto-renewable subscription.
            case renewal
            
        }
        
        // MARK: - Private
        
        private let _storeKitTransaction: Any?
        
        // Workaround to make offer variable available for specific OS versions
        private let _offer: Qonversion.Transaction.Offer?
        
        init(transaction: SKPaymentTransaction, product: SKProduct) {
            self.jsonRepresentation = nil
            self.id = transaction.transactionIdentifier
            self.originalId = transaction.original?.transactionIdentifier
            self.productId = transaction.payment.productIdentifier
            self.subscriptionGroupId = product.subscriptionGroupIdentifier
            self.purchaseDate = transaction.transactionDate
            self.originalPurchaseDate = transaction.original?.transactionDate
            self.purchasedQuantity = transaction.payment.quantity
            self.storefront = Qonversion.Storefront(countryCode: SKPaymentQueue.default().storefront?.countryCode, id: SKPaymentQueue.default().storefront?.identifier)
            self.price = product.price as Decimal
            
            let currencyCode: String?
            if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
                currencyCode = product.priceLocale.currency?.identifier
            } else {
                currencyCode = product.priceLocale.currencyCode
            }
            
            self.currency = Qonversion.Currency(identifier: currencyCode, symbol: product.priceLocale.currencySymbol)
            
            self._offer = nil
            self._storeKitTransaction = nil
            self.skPaymentTransaction = transaction
        }
        
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        init(transaction: StoreKit.Transaction) {
            self.jsonRepresentation = transaction.jsonRepresentation
            self.id = String(transaction.id)
            self.originalId = String(transaction.originalID)
            self.productId = transaction.productID
            self.subscriptionGroupId = transaction.subscriptionGroupID
            self.purchaseDate = transaction.purchaseDate
            self.originalPurchaseDate = transaction.originalPurchaseDate
            self.purchasedQuantity = transaction.purchasedQuantity
            self.price = transaction.price
            
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) {
                self.currency = Qonversion.Currency(identifier: transaction.currency?.identifier, symbol: transaction.currency?.currencySymbol())
            } else {
                self.currency = Qonversion.Currency(identifier: transaction.currencyCode, symbol: transaction.currencyCode?.toCurrencySymbol())
            }
            
            if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
                self.storefront = Qonversion.Storefront(countryCode: transaction.storefront.countryCode, id: transaction.storefront.id)
            } else {
                self.storefront = Qonversion.Storefront(countryCode: transaction.storefrontCountryCode, id: nil)
            }
            
            if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *) {
                self._offer = Qonversion.Transaction.Offer(with: transaction)
            } else {
                self._offer = nil
            }
            self._storeKitTransaction = transaction
            self.skPaymentTransaction = nil
        }
    }
}
