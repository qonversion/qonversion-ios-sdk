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
            static func from(transaction: StoreKit.Transaction?) -> Qonversion.Transaction.Offer.OfferType? {
                guard let transaction: StoreKit.Transaction = transaction else { return nil }
               
                if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *),
                    let type: StoreKit.Transaction.OfferType = transaction.offer?.type {
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
                } else {
                    guard let type: StoreKit.Transaction.OfferType = transaction.offerType else { return nil }
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
        }
        
        public enum PaymentMode: String {
            case freeTrial
            case payAsYouGo
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
        
        let id: String?
        let type: Qonversion.Transaction.Offer.OfferType?
        
        @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
        var paymentMode: Qonversion.Transaction.Offer.PaymentMode? {
            guard let offer = _offer as? StoreKit.Transaction.Offer else { return nil }
            return Qonversion.Transaction.Offer.PaymentMode.from(paymentMode: offer.paymentMode)
        }
        
        @available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
        var storeOffer: StoreKit.Transaction.Offer? { _offer as? StoreKit.Transaction.Offer }
        
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
        
    }
    
    public enum Reason: String {
        case purchase
        case renewal
    }
    
    public var jsonRepresentation: Data?

    public let id: String?

    public let originalID: String?

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var webOrderLineItemID: String? { storeKitTransaction?.webOrderLineItemID }

    public let productID: String

    public let subscriptionGroupID: String?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var appBundleID: String? { storeKitTransaction?.appBundleID }

    public let purchaseDate: Date?

    public let originalPurchaseDate: Date?

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var expirationDate: Date? { storeKitTransaction?.expirationDate }

    public let purchasedQuantity: Int

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var isUpgraded: Bool? { storeKitTransaction?.isUpgraded }

    private let _offer: Qonversion.Transaction.Offer?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var offer: Qonversion.Transaction.Offer? { _offer }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var revocationDate: Date? { storeKitTransaction?.revocationDate }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var appAccountToken: UUID? { storeKitTransaction?.appAccountToken }
    
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    public var environment: Qonversion.Transaction.Environment? { Qonversion.Transaction.Environment(rawValue: storeKitTransaction?.environment.rawValue ?? "") }
    
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    public var reason: Qonversion.Transaction.Reason {
        guard let storeKitTransaction = storeKitTransaction,
              let reason = Qonversion.Transaction.Reason(rawValue: storeKitTransaction.reason.rawValue)
        else { return Qonversion.Transaction.Reason.purchase }
        
        return reason
    }
    
    public let price: Decimal?
    
    public let currency: Qonversion.Transaction.Currency?
    
    public let storefront: Storefront?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var deviceVerification: Data? { storeKitTransaction?.deviceVerification }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var deviceVerificationNonce: UUID? { storeKitTransaction?.deviceVerificationNonce }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var signedDate: Date? { storeKitTransaction?.signedDate }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var ownershipType: Qonversion.Transaction.OwnershipType {
        guard let storeKitTransaction = storeKitTransaction,
              let ownershipType = Qonversion.Transaction.OwnershipType(rawValue: storeKitTransaction.ownershipType.rawValue)
        else { return Qonversion.Transaction.OwnershipType.purchased }
        
        return ownershipType
    }
    
    private let _storeKitTransaction: Any?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    public var storeKitTransaction: StoreKit.Transaction? { _storeKitTransaction as? StoreKit.Transaction }
    
    public var skPaymentTransaction: SKPaymentTransaction?
    
    init(transaction: SKPaymentTransaction, product: SKProduct) {
        self.jsonRepresentation = nil
        self.id = transaction.transactionIdentifier
        self.originalID = transaction.original?.transactionIdentifier
        self.productID = transaction.payment.productIdentifier
        self.subscriptionGroupID = product.subscriptionGroupIdentifier
        self.purchaseDate = transaction.transactionDate
        self.originalPurchaseDate = transaction.original?.transactionDate
        self.purchasedQuantity = transaction.payment.quantity
        self.storefront = Qonversion.Storefront(countryCode: SKPaymentQueue.default().storefront?.countryCode, id: SKPaymentQueue.default().storefront?.identifier)
        self.price = product.price as Decimal
        
        if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
            self.currency = Qonversion.Transaction.Currency(identifier: product.priceLocale.currency?.identifier, symbol: product.priceLocale.currencySymbol)
        } else {
            self.currency = Qonversion.Transaction.Currency(identifier: product.priceLocale.currencyCode, symbol: product.priceLocale.currencySymbol)
        }
        
        self._offer = nil
        self._storeKitTransaction = nil
        self.skPaymentTransaction = transaction
    }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    init(transaction: StoreKit.Transaction) {
        self.jsonRepresentation = transaction.jsonRepresentation
        self.id = String(transaction.id)
        self.originalID = String(transaction.originalID)
        self.productID = transaction.productID
        self.subscriptionGroupID = transaction.subscriptionGroupID
        self.purchaseDate = transaction.purchaseDate
        self.originalPurchaseDate = transaction.originalPurchaseDate
        self.purchasedQuantity = transaction.purchasedQuantity
        self.price = transaction.price
        
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) {
            self.currency = Qonversion.Transaction.Currency(identifier: transaction.currency?.identifier, symbol: transaction.currency?.currencySymbol())
        } else {
            self.currency = Qonversion.Transaction.Currency(identifier: transaction.currencyCode, symbol: transaction.currencyCode?.toCurrencySymbol())
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
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension Locale.Currency {
    func currencySymbol() -> String? {
        let locale: Locale? = Locale.availableIdentifiers.map { Locale(identifier: $0) }.first { $0.currencyCode == identifier }
        
        return locale?.currencySymbol
    }
}
