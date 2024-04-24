//
//  Product.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2024.
//

import Foundation
import StoreKit

extension Qonversion {
    
    public struct Product: Decodable {
        
        /// The unique Qonversion product identifier.
        public let qonversionId: String
        
        /// The unique AppStore product identifier.
        public let storeId: String
        
        /// The unique Qonversion offering identifier if product linked to an offering or nil.
        public let offeringId: String?
        
        /// The localized display name of the product, if it exists.
        public var displayName: String? {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeProduct {
                return storeProduct.displayName
            } else if let skProduct {
                return skProduct.localizedTitle
            }
            
            return nil
        }
        
        /// The localized description of the product.
        public var description: String? {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeProduct {
                return storeProduct.description
            } else if let skProduct {
                return skProduct.localizedDescription
            }
            
            return nil
        }
        
        /// The localized string representation of the product price, suitable for display.
        public var displayPrice: String? {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeProduct {
                return storeProduct.displayPrice
            } else if let skProduct {
                return skProduct.displayPrice()
            }
            
            return nil
        }
        
        /// The decimal representation of the cost of the product, in local currency.
        public var price: Decimal? {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeProduct {
                return storeProduct.price
            } else if let skProduct {
                return skProduct.price as Decimal
            }
            
            return nil
        }

        /// The raw JSON representation of the product information.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var jsonRepresentation: Data? { storeProduct?.jsonRepresentation }
        
        /// Whether the product is available for family sharing.
        @available(iOS 14.0, macOS 11.0, watchOS 7.0, visionOS 1.0, *)
        public var isFamilyShareable: Bool? {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let product = storeProduct {
                return product.isFamilyShareable
            } else if let product = skProduct {
                return product.isFamilyShareable
            }
            
            return nil
        }
        
        /// The format style to use when formatting numbers derived from the price for the product.
        ///
        /// Use `displayPrice` when possible. Use `priceFormatStyle` only for localizing numbers
        /// derived from the `price` property, such as "2 products for $(`price * 2`)".
        /// - Important: When using `priceFormatStyle` on systems earlier than iOS 16.0,
        ///              macOS 13.0, tvOS 16.0 or watchOS 9.0, the property may return a format style
        ///              with a sentinel locale with identifier "xx\_XX" in some uncommon cases:
        ///              (1) StoreKit Testing in Xcode (workaround: test your app on a device running a
        ///              more recent OS) or (2) a critical server error.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        @backDeployed(before: iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, macCatalyst 16.0)
        public var priceFormatStyle: Decimal.FormatStyle.Currency? { storeProduct?.priceFormatStyle }
        
        /// The original StoreKit product.
        ///
        /// For StoreKit 2 product use ``Qonversion/Qonversion/Product/storeProduct`` .
        public var skProduct: SKProduct?
        
        /// Whether the store product is loaded and linked or not.
        public var isStoreProductLinked: Bool {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *) {
                return storeProduct != nil || skProduct != nil
            } else {
                return skProduct != nil
            }
        }

        /// The type of the product.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var type: Qonversion.Product.ProductType? { Qonversion.Product.ProductType.from(type: storeProduct?.type) }
        
        // The original StoreKit 2 product.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        public var storeProduct: StoreKit.Product? { _storeProduct as? StoreKit.Product }
        
        /// The format style to use when formatting subscription periods for the subscription.
        ///
        /// Use the `formatted(_:referenceDate:)` method on `Product.SubscriptionPeriod`
        /// with this style to format the subscription period for the App Store locale for the subscription.
        /// - Important: When using `subscriptionPeriodFormatStyle` on systems earlier than
        ///              iOS 16.0, macOS 13.0, tvOS 16.0 or watchOS 9.0, the property may return a
        ///              format style with a sentinel locale with identifier "xx\_XX" in some uncommon cases:
        ///              (1) StoreKit Testing in Xcode (workaround: test your app on a device running a
        ///              more recent OS) or (2) a critical server error.
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        @backDeployed(before: iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, macCatalyst 16.0)
        public var subscriptionPeriodFormatStyle: Date.ComponentsFormatStyle? { storeProduct?.subscriptionPeriodFormatStyle }
        
        /// The format style to use when formatting subscription period units for the subscription.
        ///
        /// Use the `formatted(_:)` method on `Product.SubscriptionPeriod.Unit` with this
        /// style to format the subscription period for the App Store locale for the subscription.
        @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
        public var subscriptionPeriodUnitFormatStyle: StoreKit.Product.SubscriptionPeriod.Unit.FormatStyle? { storeProduct?.subscriptionPeriodUnitFormatStyle }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            qonversionId = try container.decode(String.self, forKey: .qonversionId)
            storeId = try container.decode(String.self, forKey: .storeId)
            offeringId = try container.decode(String.self, forKey: .offeringId)
            skProduct = nil
        }
        
        // MARK: - Nested structures and enums
        
        /// A unit of time.
        public struct SubscriptionPeriod {
            
            public enum Unit {
                
                /// A subscription period unit of a day.
                case day

                /// A subscription period unit of a week.
                case week

                /// A subscription period unit of a month.
                case month

                /// A subscription period unit of a year.
                case year
                
                @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
                static func from(unit: StoreKit.Product.SubscriptionPeriod.Unit?) -> Qonversion.Product.SubscriptionPeriod.Unit? {
                    guard let unit: StoreKit.Product.SubscriptionPeriod.Unit = unit else { return nil }

                    switch unit {
                    case .day:
                        return .day
                    case .week:
                        return .week
                    case .month:
                        return .month
                    case .year:
                        return .year
                    default:
                        return nil
                    }
                }
                
            }
            
            /// The unit of time that this period represents.
            public let unit: Qonversion.Product.SubscriptionPeriod.Unit

            /// The number of units that the period represents.
            public let value: Int
        }
        
        /// Information about a subscription offer configured in App Store Connect.
        public struct SubscriptionOffer {
            
            /// The type of the subscription offer.
            public enum OfferType {
                
                /// An introductory offer for a subscription.
                case  introductory
                
                /// A promotional offer.
                case promotional
                
                @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
                static func from(offerType: StoreKit.Product.SubscriptionOffer.OfferType?) -> Qonversion.Product.SubscriptionOffer.OfferType? {
                    guard let offerType: StoreKit.Product.SubscriptionOffer.OfferType = offerType else { return nil }

                    switch offerType {
                    case .introductory:
                        return .introductory
                    case .promotional:
                        return .promotional
                    default:
                        return nil
                    }
                }
            }
            
            public enum PaymentMode {
                
                /// A payment mode of a product discount that indicates the discount applies over a single billing period or multiple billing periods.
                case payAsYouGo

                /// A payment mode of a product discount that indicates the system applies the discount up front.
                case payUpFront

                /// A payment mode of a product discount that indicates a free trial offer.
                case freeTrial
                
                @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
                static func from(paymentMode: StoreKit.Product.SubscriptionOffer.PaymentMode?) -> Qonversion.Product.SubscriptionOffer.PaymentMode? {
                    guard let mode: StoreKit.Product.SubscriptionOffer.PaymentMode = paymentMode else { return nil }

                    switch mode {
                    case .payUpFront:
                        return .payUpFront
                    case .payAsYouGo:
                        return .payAsYouGo
                    case .freeTrial:
                        return .freeTrial
                    default:
                        return nil
                    }
                }
                
            }
            
            /// The promotional offer identifier.
            ///
            /// This is always `nil` for introductory offers and never `nil` for promotional offers.
            public let id: String?

            /// The type of the offer.
            public let type: Qonversion.Product.SubscriptionOffer.OfferType

            /// The discounted price that the offer provides in local currency.
            ///
            /// This is the price per period in the case of `.payAsYouGo`
            public let price: Decimal

            /// A localized string representation of `price`.
            public let displayPrice: String

            /// The duration that this offer lasts before auto-renewing or changing to standard subscription
            /// renewals.
            public let period: Qonversion.Product.SubscriptionPeriod

            /// The number of periods this offer will renew for.
            ///
            /// Always 1 except for `.payAsYouGo`.
            public let periodCount: Int

            /// How the user is charged for this offer.
            public let paymentMode: Qonversion.Product.SubscriptionOffer.PaymentMode
        }
        
        public struct SubscriptionInfo {
            
            /// An optional introductory offer that will automatically be applied if the user is eligible.
            public let introductoryOffer: Qonversion.Product.SubscriptionOffer?

            /// An array of all the promotional offers configured for this subscription.
            public let promotionalOffers: [Qonversion.Product.SubscriptionOffer]

            /// The group identifier for this subscription.
            public let subscriptionGroupID: String

            /// The duration that this subscription lasts before auto-renewing.
            public let subscriptionPeriod: Product.SubscriptionPeriod
        }
        
        public enum ProductType {
            
            /// A consumable in-app purchase.
            case consumable
            
            /// A non-consumable in-app purchase.
            case nonConsumable
            
            /// A non-renewing subscription.
            case nonRenewable
            
            /// An auto-renewable subscription.
            case autoRenewable
            
            @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
            static func from(type: StoreKit.Product.ProductType?) -> Qonversion.Product.ProductType? {
                guard let type: StoreKit.Product.ProductType = type else { return nil }

                switch type {
                case .consumable:
                    return .consumable
                case .nonConsumable:
                    return .nonConsumable
                case .nonRenewable:
                    return .nonRenewable
                case .autoRenewable:
                    return .autoRenewable
                default:
                    return nil
                }
            }
        }
        
        // MARK: - Private
        
        // Internal workaround
        var _storeProduct: Any?
        
        @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
        mutating func enrich(storeProduct: StoreKit.Product) {
            self._storeProduct = storeProduct
        }
        
        mutating func enrich(skProduct: SKProduct) {
            self.skProduct = skProduct
        }
        
        private enum CodingKeys: String, CodingKey {
            case qonversionId
            case storeId
            case offeringId
        }
        
    }
    
}
