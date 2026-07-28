//
//  Product.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.04.2024.
//

import Foundation
import StoreKit

extension Qonversion {
    
    // @unchecked: the StoreKit products inside are reference types managed by
    // StoreKit itself.
    public struct Product: Codable, @unchecked Sendable {
        
        /// The unique Qonversion product identifier.
        public let qonversionId: String
        
        /// The AppStore product identifier.
        public let storeId: String

        /// The localized display name of the product, if it exists.
        public var displayName: String? { storeProduct?.displayName }

        /// The localized description of the product.
        public var description: String? { storeProduct?.description }

        /// The localized string representation of the product price, suitable for display.
        public var displayPrice: String? { storeProduct?.displayPrice }

        /// The decimal representation of the cost of the product, in local currency.
        public var price: Decimal? { storeProduct?.price }

        /// The raw JSON representation of the product information.
        public var jsonRepresentation: Data? { storeProduct?.jsonRepresentation }

        /// Whether the product is available for family sharing.
        public var isFamilyShareable: Bool? { storeProduct?.isFamilyShareable }
        
        /// The format style to use when formatting numbers derived from the price for the product.
        ///
        /// Use `displayPrice` when possible. Use `priceFormatStyle` only for localizing numbers
        /// derived from the `price` property, such as "2 products for $(`price * 2`)".
        /// - Important: When using `priceFormatStyle` on systems earlier than iOS 16.0,
        ///              macOS 13.0, tvOS 16.0 or watchOS 9.0, the property may return a format style
        ///              with a sentinel locale with identifier "xx\_XX" in some uncommon cases:
        ///              (1) StoreKit Testing in Xcode (workaround: test your app on a device running a
        ///              more recent OS) or (2) a critical server error.
        @backDeployed(before: iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, macCatalyst 16.0)
        public var priceFormatStyle: Decimal.FormatStyle.Currency? { storeProduct?.priceFormatStyle }

        /// Whether the store product is loaded and linked or not.
        public var isStoreProductLinked: Bool { _storeProduct != nil }

        /// The type of the product.
        public var type: Qonversion.Product.ProductType? { Qonversion.Product.ProductType.from(type: storeProduct?.type) }

        // The original StoreKit 2 product.
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
        @backDeployed(before: iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, macCatalyst 16.0)
        public var subscriptionPeriodFormatStyle: Date.ComponentsFormatStyle? { storeProduct?.subscriptionPeriodFormatStyle }
        
        /// The format style to use when formatting subscription period units for the subscription.
        ///
        /// Use the `formatted(_:)` method on `Product.SubscriptionPeriod.Unit` with this
        /// style to format the subscription period for the App Store locale for the subscription.
        @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
        public var subscriptionPeriodUnitFormatStyle: StoreKit.Product.SubscriptionPeriod.Unit.FormatStyle? { storeProduct?.subscriptionPeriodUnitFormatStyle }
        
        /// Properties and functionality specific to auto-renewable subscriptions.
        ///
        /// This is never `nil` if `type` is `.autoRenewable`, and always `nil` for all other product
        /// types.
        public var subscription: Qonversion.Product.SubscriptionInfo?
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            qonversionId = try container.decode(String.self, forKey: .qonversionId)
            // Two spellings of the same field: the v4 API answers
            // `apple_product_id`, the fallback file shipped by the previous SDK
            // generation writes `store_id` (QNMapper.m) and MIGRATION.md
            // promises that shape keeps working. `store_id` wins when both are
            // there — it is the explicit one.
            // Products without an App Store id at all (e.g. Stripe/Play-only)
            // decode with an empty storeId instead of failing the whole list;
            // ProductsManager logs them so it is never silent.
            let storeIdentifier: String? = try container.decodeIfPresent(String.self, forKey: .legacyStoreId)
                ?? container.decodeIfPresent(String.self, forKey: .storeId)
            storeId = storeIdentifier ?? ""
        }

        /// Only the wire fields round-trip — StoreKit enrichment is runtime
        /// state and is re-applied after decoding.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(qonversionId, forKey: .qonversionId)
            try container.encode(storeId, forKey: .storeId)
        }

        init(qonversionId: String, storeId: String) {
            self.qonversionId = qonversionId
            self.storeId = storeId
        }
        
        // MARK: - Nested structures and enums
        
        /// Subscription period details..
        public struct SubscriptionPeriod: Sendable {
            
            /// The unit of time that this period represents.
            public let unit: Qonversion.Product.SubscriptionPeriod.Unit

            /// The number of units that the period represents.
            public let value: Int
            
            init(unit: Qonversion.Product.SubscriptionPeriod.Unit, value: Int) {
                self.unit = unit
                self.value = value
            }

            init(originalPeriod: StoreKit.Product.SubscriptionPeriod) {
                value = originalPeriod.value
                unit = Qonversion.Product.SubscriptionPeriod.Unit.from(unit: originalPeriod.unit)
            }
            
            // MARK: Nested structs & enums
            
            /// Unit type of a subscription period.
            public enum Unit: Sendable {
                
                /// For rare cases when the subscription period unit can't be determined.
                case unknown
                
                /// A subscription period unit of a day.
                case day

                /// A subscription period unit of a week.
                case week

                /// A subscription period unit of a month.
                case month

                /// A subscription period unit of a year.
                case year
                
                static func from(unit: StoreKit.Product.SubscriptionPeriod.Unit?) -> Qonversion.Product.SubscriptionPeriod.Unit {
                    guard let unit: StoreKit.Product.SubscriptionPeriod.Unit = unit else { return .unknown }

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
                        return .unknown
                    }
                }

                
            }
        }
        
        /// Information about a subscription offer configured in App Store Connect.
        // @unchecked: the StoreKit offer inside is a value managed by
        // StoreKit itself, like the store product on Product.
        public struct SubscriptionOffer: @unchecked Sendable {
            
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

            /// The store offer this one was built from. Required to purchase
            /// with a win-back offer, which StoreKit accepts only as its own
            /// object.
            var originalOffer: StoreKit.Product.SubscriptionOffer? { _originalOffer as? StoreKit.Product.SubscriptionOffer }

            // Workaround to keep the struct usable where StoreKit types are not.
            private let _originalOffer: Any?

            init(id: String?, type: Qonversion.Product.SubscriptionOffer.OfferType, price: Decimal, displayPrice: String, period: Qonversion.Product.SubscriptionPeriod, periodCount: Int, paymentMode: Qonversion.Product.SubscriptionOffer.PaymentMode) {
                self._originalOffer = nil
                self.id = id
                self.type = type
                self.price = price
                self.displayPrice = displayPrice
                self.period = period
                self.periodCount = periodCount
                self.paymentMode = paymentMode
            }

            init?(originalOffer: StoreKit.Product.SubscriptionOffer?) {
                guard let originalOffer else { return nil }
                _originalOffer = originalOffer
                id = originalOffer.id
                type = Qonversion.Product.SubscriptionOffer.OfferType.from(offerType: originalOffer.type)
                price = originalOffer.price
                displayPrice = originalOffer.displayPrice
                period = Qonversion.Product.SubscriptionPeriod(originalPeriod: originalOffer.period)
                periodCount = originalOffer.periodCount
                paymentMode = Qonversion.Product.SubscriptionOffer.PaymentMode.from(paymentMode: originalOffer.paymentMode)
            }

            
            // MARK: Nested structs & enums
            
            /// The type of the subscription offer.
            public enum OfferType: Sendable {
                
                /// In case the offer type can't be determined.
                case unknown
                
                /// An introductory offer for a subscription.
                case introductory
                
                /// A promotional offer.
                case promotional

                /// A win-back offer, shown to a lapsed subscriber (iOS 18+).
                case winBack

                static func from(offerType: StoreKit.Product.SubscriptionOffer.OfferType?) -> Qonversion.Product.SubscriptionOffer.OfferType {
                    guard let offerType else { return .unknown }

                    if #available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *), offerType == .winBack {
                        return .winBack
                    }

                    switch offerType {
                    case .introductory:
                        return .introductory
                    case .promotional:
                        return .promotional
                    default:
                        return .unknown
                    }
                }

            }
            
            /// Payment mode for a product
            public enum PaymentMode: Sendable {
                
                /// For rare cases when the payment mode can't be determined.
                case unknown
                
                /// A payment mode of a product discount that indicates the discount applies over a single billing period or multiple billing periods.
                case payAsYouGo

                /// A payment mode of a product discount that indicates the system applies the discount up front.
                case payUpFront

                /// A payment mode of a product discount that indicates a free trial offer.
                case freeTrial
                
                static func from(paymentMode: StoreKit.Product.SubscriptionOffer.PaymentMode?) -> Qonversion.Product.SubscriptionOffer.PaymentMode {
                    guard let mode: StoreKit.Product.SubscriptionOffer.PaymentMode = paymentMode else { return .unknown }

                    switch mode {
                    case .payUpFront:
                        return .payUpFront
                    case .payAsYouGo:
                        return .payAsYouGo
                    case .freeTrial:
                        return .freeTrial
                    default:
                        return .unknown
                    }
                }

                
            }
        }
        
        /// Information about an auto-renewable subscription, such as its status, period, subscription group, and subscription offer details.
        public struct SubscriptionInfo: Sendable {
            
            /// An optional introductory offer that will automatically be applied if the user is eligible.
            public let introductoryOffer: Qonversion.Product.SubscriptionOffer?

            /// An array of all the promotional offers configured for this subscription.
            public let promotionalOffers: [Qonversion.Product.SubscriptionOffer]

            /// The win-back offers configured for this subscription, for
            /// lapsed subscribers. Always empty below iOS 18.
            public let winBackOffers: [Qonversion.Product.SubscriptionOffer]

            /// The group identifier for this subscription.
            public let subscriptionGroupId: String

            /// The duration that this subscription lasts before auto-renewing.
            public let subscriptionPeriod: Qonversion.Product.SubscriptionPeriod
            
            init(subscriptionGroupId: String, subscriptionPeriod: Qonversion.Product.SubscriptionPeriod, introductoryOffer: Qonversion.Product.SubscriptionOffer? = nil, promotionalOffers: [Qonversion.Product.SubscriptionOffer] = [], winBackOffers: [Qonversion.Product.SubscriptionOffer] = []) {
                self.subscriptionGroupId = subscriptionGroupId
                self.subscriptionPeriod = subscriptionPeriod
                self.introductoryOffer = introductoryOffer
                self.promotionalOffers = promotionalOffers
                self.winBackOffers = winBackOffers
            }

            init?(originalSubscription: StoreKit.Product.SubscriptionInfo?) {
                guard let originalSubscription else { return nil }
                
                introductoryOffer = Qonversion.Product.SubscriptionOffer(originalOffer: originalSubscription.introductoryOffer)
                promotionalOffers = originalSubscription.promotionalOffers.compactMap {
                    Qonversion.Product.SubscriptionOffer(originalOffer: $0)
                }
                if #available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
                    winBackOffers = originalSubscription.winBackOffers.compactMap {
                        Qonversion.Product.SubscriptionOffer(originalOffer: $0)
                    }
                } else {
                    winBackOffers = []
                }
                subscriptionGroupId = originalSubscription.subscriptionGroupID
                subscriptionPeriod = Qonversion.Product.SubscriptionPeriod(originalPeriod: originalSubscription.subscriptionPeriod)
            }

        }
        
        /// The types of in-app purchases.
        public enum ProductType: Sendable {
            
            /// A consumable in-app purchase.
            case consumable
            
            /// A non-consumable in-app purchase.
            case nonConsumable
            
            /// A non-renewing subscription.
            case nonRenewable
            
            /// An auto-renewable subscription.
            case autoRenewable
            
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
        
        mutating func enrich(storeProduct: StoreKit.Product) {
            self._storeProduct = storeProduct
            self.subscription = Qonversion.Product.SubscriptionInfo(originalSubscription: storeProduct.subscription)
        }
        
        private enum CodingKeys: String, CodingKey {
            case qonversionId = "id"
            case storeId = "apple_product_id"
            /// The fallback file's spelling of `storeId` — see init(from:).
            case legacyStoreId = "store_id"
        }
    }
}
