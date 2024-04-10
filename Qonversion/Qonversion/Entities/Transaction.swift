//
//  Transaction.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 01.03.2024.
//

import Foundation
import StoreKit

public enum RevocationReason {
    case developerIssue
    case other
}

public struct Storefront {
    public let countryCode: String

    /// A value defined by Apple that uniquely identifies an App Store storefront.
    public let id: String?
    
    init?(countryCode: String?, id: String?) {
        guard let countryCode: String = countryCode else { return nil }
        
        self.countryCode = countryCode
        self.id = id
    }
}

public struct Transaction {
    
    public enum OwnershipType: String {
        case purchased
        case familyShared
    }
    
    public struct Currency {
        
        public let identifier: String
        public let symbol: String?
        
        init?(identifier: String?, symbol: String?) {
            guard let identifier = identifier else { return nil }
            
            self.identifier = identifier
            self.symbol = symbol
        }
        
    }
    
    public enum Environment: String {
        case production
        case sandbox
        case xcode
    }
    
    public struct Offer {
        
        public enum OfferType: String {
            case introductory
            case promotional
            case code
            
            @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
            static func from(transaction: StoreKit.Transaction?) -> Transaction.Offer.OfferType? {
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
                    return Transaction.Offer.OfferType.introductory
                case .promotional:
                    return Transaction.Offer.OfferType.promotional
                case .code:
                    return Transaction.Offer.OfferType.code
                default:
                    return nil
                }
            }
        }
        
        public enum PaymentMode: String {
            case freeTrial
            case payAsYouGo
            case payUpFront
            
            @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
            static func from(paymentMode: StoreKit.Transaction.Offer.PaymentMode?) -> Transaction.Offer.PaymentMode? {
                guard let paymentMode = paymentMode else { return nil }
                switch paymentMode {
                case .freeTrial:
                    return Transaction.Offer.PaymentMode.freeTrial
                case .payAsYouGo:
                    return Transaction.Offer.PaymentMode.payAsYouGo
                case .payUpFront:
                    return Transaction.Offer.PaymentMode.payUpFront
                default:
                    return nil
                }
            }
        }
        
        let id: String?
        let type: Transaction.Offer.OfferType?
        
        @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
        var paymentMode: Transaction.Offer.PaymentMode? {
            guard let offer = _offer as? StoreKit.Transaction.Offer else { return nil }
            return Transaction.Offer.PaymentMode.from(paymentMode: offer.paymentMode)
        }
        
        @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
        var originalOffer: StoreKit.Transaction.Offer? { _offer as? StoreKit.Transaction.Offer }
        
        // Workaround to make originalOffer variable available for specific OS versions
        let _offer: Any?
        
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        init?(with transaction: StoreKit.Transaction) {
            self.type = Transaction.Offer.OfferType.from(transaction: transaction)
            
            if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *) {
                guard let offer = transaction.offer else { return nil }
                
                self._offer = offer
                self.id = offer.id
            } else {
                self.id = transaction.offerID
                self._offer = nil
            }
        }
        
    }
    
    public enum Reason: String {
        case purchase
        case renewal
    }
    
    public var jsonRepresentation: Data?

    public let id: String?

    public let originalId: String?

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var webOrderLineItemId: String? { storeKitTransaction?.webOrderLineItemID }

    public let productId: String

    public let subscriptionGroupId: String?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var appBundleId: String? { storeKitTransaction?.appBundleID }

    public let purchaseDate: Date?

    public let originalPurchaseDate: Date?

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var expirationDate: Date? { storeKitTransaction?.expirationDate }

    public let purchasedQuantity: Int

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var isUpgraded: Bool? { storeKitTransaction?.isUpgraded }

    // Workaround to make offer variable available for specific OS versions
    private let _offer: Transaction.Offer?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var offer: Transaction.Offer? { _offer }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var revocationDate: Date? { storeKitTransaction?.revocationDate }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var appAccountToken: UUID? { storeKitTransaction?.appAccountToken }
    
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    public var environment: Transaction.Environment? { Transaction.Environment(rawValue: storeKitTransaction?.environment.rawValue ?? "") }
    
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    public var reason: Transaction.Reason {
        guard let storeKitTransaction = storeKitTransaction,
              let reason = Transaction.Reason(rawValue: storeKitTransaction.reason.rawValue)
        else { return Transaction.Reason.purchase }
        
        return reason
    }
    
    public let price: Decimal?
    
    public let currency: Transaction.Currency?
    
    public let storefront: Storefront?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var deviceVerification: Data? { storeKitTransaction?.deviceVerification }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var deviceVerificationNonce: UUID? { storeKitTransaction?.deviceVerificationNonce }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var signedDate: Date? { storeKitTransaction?.signedDate }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var ownershipType: Transaction.OwnershipType {
        guard let storeKitTransaction = storeKitTransaction,
              let ownershipType = Transaction.OwnershipType(rawValue: storeKitTransaction.ownershipType.rawValue)
        else { return Transaction.OwnershipType.purchased }
        
        return ownershipType
    }
    
    private let _storeKitTransaction: Any?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var storeKitTransaction: StoreKit.Transaction? { _storeKitTransaction as? StoreKit.Transaction }
    
    public let skPaymentTransaction: SKPaymentTransaction?
    
    init(transaction: SKPaymentTransaction, product: SKProduct) {
        self.jsonRepresentation = nil
        self.id = transaction.transactionIdentifier
        self.originalId = transaction.original?.transactionIdentifier
        self.productId = transaction.payment.productIdentifier
        self.subscriptionGroupId = product.subscriptionGroupIdentifier
        self.purchaseDate = transaction.transactionDate
        self.originalPurchaseDate = transaction.original?.transactionDate
        self.purchasedQuantity = transaction.payment.quantity
        self.storefront = Storefront(countryCode: SKPaymentQueue.default().storefront?.countryCode, id: SKPaymentQueue.default().storefront?.identifier)
        self.price = product.price as Decimal
        
        let currencyCode: String?
        if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
            currencyCode = product.priceLocale.currency?.identifier
        } else {
            currencyCode = product.priceLocale.currencyCode
        }
        
        self.currency = Transaction.Currency(identifier: currencyCode, symbol: product.priceLocale.currencySymbol)
        
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
            self.currency = Transaction.Currency(identifier: transaction.currency?.identifier, symbol: transaction.currency?.currencySymbol())
        } else {
            self.currency = Transaction.Currency(identifier: transaction.currencyCode, symbol: transaction.currencyCode?.toCurrencySymbol())
        }
        
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
            self.storefront = Storefront(countryCode: transaction.storefront.countryCode, id: transaction.storefront.id)
        } else {
            self.storefront = Storefront(countryCode: transaction.storefrontCountryCode, id: nil)
        }
        
        if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *) {
            self._offer = Transaction.Offer(with: transaction)
        } else {
            self._offer = nil
        }
        self._storeKitTransaction = transaction
        self.skPaymentTransaction = nil
    }
}
