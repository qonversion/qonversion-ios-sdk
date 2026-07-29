//
//  Entitlement.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// A user's access right to a feature, granted by a purchase or manually.
    public struct Entitlement: Codable, Sendable {

        /// Qonversion entitlement identifier.
        public let id: String

        /// Whether the user currently has this entitlement.
        /// Note: active == true does not mean the subscription will renew.
        public let active: Bool

        /// Source of the purchase via which the entitlement was activated.
        public let source: Qonversion.Entitlement.Source

        /// A renew state of the subscription that granted the entitlement.
        public let renewState: Qonversion.Entitlement.RenewState

        /// Time at which the entitlement was started.
        public let startedDate: Date?

        /// Time at which the entitlement expires; nil for lifetime grants.
        public let expirationDate: Date?

        /// Qonversion product id that granted the entitlement.
        public let productId: String?

        /// How the entitlement was granted.
        public let grantType: Qonversion.Entitlement.GrantType

        /// Renews count for the entitlement. Counting starts from the second
        /// paid subscription period: of 20 transactions with one trial and one
        /// first paid transaction, the renews count is 18.
        public let renewsCount: Int

        /// Time at which the trial started.
        public let trialStartDate: Date?

        /// Time of the first purchase that granted the entitlement.
        public let firstPurchaseDate: Date?

        /// Time of the last purchase that granted the entitlement.
        public let lastPurchaseDate: Date?

        /// Time at which the auto-renew was turned off.
        public let autoRenewDisableDate: Date?

        /// The offer code activated last for this entitlement.
        public let lastActivatedOfferCode: String?

        /// The store transactions that unlocked the entitlement.
        public let transactions: [Qonversion.Entitlement.StoreTransaction]

        public enum Source: String, Codable, Sendable {
            case unknown
            case appStore = "appstore"
            case playStore = "playstore"
            case stripe
            case manual
        }

        /// The renew state of the subscription behind the entitlement.
        ///
        /// Only ``willRenew``, ``canceled`` and ``billingIssue`` exist as
        /// values on the wire (inside `product.subscription.renew_state`).
        /// ``nonRenewable`` and ``unknown`` are derived: the backend expresses
        /// a non-renewable purchase by sending no subscription object at all.
        /// The raw values below are the SDK's own identity for the state — the
        /// API never sends "non_renewable" or "unknown".
        public enum RenewState: String, Codable, Sendable {
            case unknown
            /// A non-renewable purchase (a consumable or a lifetime product).
            case nonRenewable = "non_renewable"
            case willRenew = "will_renew"
            case canceled
            case billingIssue = "billing_issue"

            /// The state named by a `renew_state` value, or nil when the value
            /// is not part of the vocabulary.
            ///
            /// `will_renew`, `canceled` and `billing_issue` are the three the
            /// API sends. "non_renewable" is accepted on top of them for two
            /// reasons: caches written by an earlier build of this SDK put it
            /// into `product.subscription.renew_state`, and if the backend ever
            /// does name the state explicitly, honoring it beats degrading to
            /// .unknown. It is never written back out — see ``wireValue``.
            init?(wireValue: String) {
                switch wireValue {
                case "will_renew":
                    self = .willRenew
                case "canceled":
                    self = .canceled
                case "billing_issue":
                    self = .billingIssue
                case "non_renewable":
                    self = .nonRenewable
                default:
                    return nil
                }
            }

            /// The `renew_state` value for this state, or nil when the state
            /// is not expressed by one.
            var wireValue: String? {
                switch self {
                case .willRenew, .canceled, .billingIssue:
                    return rawValue
                case .nonRenewable, .unknown:
                    return nil
                }
            }

            /// The backend's own rule (product_center) for an entitlement that
            /// carries no renew state: on a recognized store source it is a
            /// non-renewable purchase, while a manual grant simply has no
            /// store subscription to report a state for.
            ///
            /// An unrecognized source (a store this SDK version does not know
            /// yet) is treated like the manual case on purpose: no information
            /// must not turn into the affirmative claim "this never renews".
            static func derived(from source: Source) -> RenewState {
                switch source {
                case .manual, .unknown:
                    return .unknown
                case .appStore, .playStore, .stripe:
                    return .nonRenewable
                }
            }
        }

        /// How the user got the entitlement.
        public enum GrantType: String, Codable, Sendable {
            case purchase
            case familySharing = "family_sharing"
            case offerCode = "offer_code"
            case manual
        }

        /// A store transaction behind the entitlement, as the Qonversion
        /// backend knows it. This is the billing history record, not the
        /// StoreKit object — see ``Qonversion/Qonversion/Transaction`` for that.
        public struct StoreTransaction: Codable, Sendable {

            /// Store transaction identifier.
            public let transactionId: String?

            /// Original store transaction identifier.
            public let originalTransactionId: String?

            /// The offer code used for the transaction.
            public let offerCode: String?

            /// The promotional offer id used for the transaction.
            public let promoOfferId: String?

            /// Time at which the transaction happened.
            public let transactionDate: Date?

            /// Time at which the subscription of the transaction expires.
            public let expirationDate: Date?

            /// Time at which the App Store refunded the transaction or revoked
            /// it from Family Sharing.
            public let revocationDate: Date?

            /// The Apple server environment the transaction belongs to.
            public let environment: Environment

            /// Whether the transaction is owned or family-shared.
            public let ownershipType: OwnershipType

            /// What the transaction represents in the subscription lifecycle.
            public let type: TransactionType

            public enum Environment: String, Codable, Sendable {
                case sandbox
                case production
            }

            public enum OwnershipType: String, Codable, Sendable {
                case owner
                case familyShared = "family_shared"

                /// The wire spells family sharing "family_shared" here, while
                /// ``Qonversion/Qonversion/Entitlement/GrantType`` spells the
                /// same idea "family_sharing" — accept both so a payload
                /// normalized to either one keeps its meaning.
                init?(wireValue: String) {
                    switch wireValue {
                    case "family_sharing":
                        self = .familyShared
                    default:
                        self.init(rawValue: wireValue)
                    }
                }
            }

            public enum TransactionType: String, Codable, Sendable {
                case unknown
                case subscriptionStarted = "subscription_started"
                case subscriptionRenewed = "subscription_renewed"
                case trialStarted = "trial_started"
                case introStarted = "intro_started"
                case introRenewed = "intro_renewed"
                case nonConsumablePurchase = "non_consumable_purchase"

                /// "nonconsumable_purchase" is the spelling this SDK shipped
                /// with before the contract was read off the backend; keep
                /// accepting it so a normalizing proxy does not degrade the
                /// transaction to .unknown.
                init?(wireValue: String) {
                    switch wireValue {
                    case "nonconsumable_purchase":
                        self = .nonConsumablePurchase
                    default:
                        self.init(rawValue: wireValue)
                    }
                }
            }

            init(
                transactionId: String?,
                originalTransactionId: String?,
                offerCode: String? = nil,
                promoOfferId: String? = nil,
                transactionDate: Date? = nil,
                expirationDate: Date? = nil,
                revocationDate: Date? = nil,
                environment: Environment = .production,
                ownershipType: OwnershipType = .owner,
                type: TransactionType = .unknown
            ) {
                self.transactionId = transactionId
                self.originalTransactionId = originalTransactionId
                self.offerCode = offerCode
                self.promoOfferId = promoOfferId
                self.transactionDate = transactionDate
                self.expirationDate = expirationDate
                self.revocationDate = revocationDate
                self.environment = environment
                self.ownershipType = ownershipType
                self.type = type
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
                originalTransactionId = try container.decodeIfPresent(String.self, forKey: .originalTransactionId)
                offerCode = try container.decodeIfPresent(String.self, forKey: .offerCode)
                promoOfferId = try container.decodeIfPresent(String.self, forKey: .promoOfferId)
                transactionDate = container.decodeTolerantDate(forKey: .transactionDate)
                expirationDate = container.decodeTolerantDate(forKey: .expirationDate)
                revocationDate = container.decodeTolerantDate(forKey: .revocationDate)

                // Production defaults: an unknown value must never fail the
                // decode of the user's access list.
                let rawEnvironment = try container.decodeIfPresent(String.self, forKey: .environment)
                environment = rawEnvironment.flatMap { Environment(rawValue: $0) } ?? .production
                let rawOwnershipType = try container.decodeIfPresent(String.self, forKey: .ownershipType)
                ownershipType = rawOwnershipType.flatMap { OwnershipType(wireValue: $0) } ?? .owner
                let rawType = try container.decodeIfPresent(String.self, forKey: .type)
                type = rawType.flatMap { TransactionType(wireValue: $0) } ?? .unknown
            }

            private enum CodingKeys: String, CodingKey {
                case transactionId = "transaction_id"
                case originalTransactionId = "original_transaction_id"
                case offerCode = "offer_code"
                case promoOfferId = "promo_offer_id"
                case transactionDate = "transaction_timestamp"
                case expirationDate = "expiration_timestamp"
                case revocationDate = "transaction_revoke_timestamp"
                case environment
                case ownershipType = "ownership_type"
                case type
            }
        }

        init(
            id: String,
            active: Bool,
            source: Qonversion.Entitlement.Source,
            renewState: Qonversion.Entitlement.RenewState = .unknown,
            startedDate: Date? = nil,
            expirationDate: Date? = nil,
            productId: String? = nil,
            grantType: Qonversion.Entitlement.GrantType = .purchase,
            renewsCount: Int = 0,
            trialStartDate: Date? = nil,
            firstPurchaseDate: Date? = nil,
            lastPurchaseDate: Date? = nil,
            autoRenewDisableDate: Date? = nil,
            lastActivatedOfferCode: String? = nil,
            transactions: [Qonversion.Entitlement.StoreTransaction] = []
        ) {
            self.id = id
            self.active = active
            self.source = source
            self.renewState = renewState
            self.startedDate = startedDate
            self.expirationDate = expirationDate
            self.productId = productId
            self.grantType = grantType
            self.renewsCount = renewsCount
            self.trialStartDate = trialStartDate
            self.firstPurchaseDate = firstPurchaseDate
            self.lastPurchaseDate = lastPurchaseDate
            self.autoRenewDisableDate = autoRenewDisableDate
            self.lastActivatedOfferCode = lastActivatedOfferCode
            self.transactions = transactions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // The id is the only strict field: an entitlement without one
            // cannot be keyed, served or matched against anything.
            id = try container.decode(String.self, forKey: .id)
            active = (try? container.decodeIfPresent(Bool.self, forKey: .active)) ?? false

            let rawSource: String? = try? container.decodeIfPresent(String.self, forKey: .source)
            source = rawSource.flatMap { Source(rawValue: $0) } ?? .unknown

            // Tolerant like every other field: one malformed date must
            // degrade that field, not drop the whole entitlement (and with it
            // the user's access) from the list.
            startedDate = container.decodeTolerantDate(forKey: .started)
            expirationDate = container.decodeTolerantDate(forKey: .expires)

            let product: EntitlementProduct? = try? container.decodeIfPresent(EntitlementProduct.self, forKey: .product)
            productId = product?.productId
            let cachedRenewState: String? = try? container.decodeIfPresent(String.self, forKey: .cachedRenewState)
            if let rawRenewState: String = product?.subscription?.renewState {
                // A renew state on the wire is authoritative; one the SDK does
                // not know degrades to .unknown rather than to a derivation
                // that would contradict it.
                renewState = RenewState(wireValue: rawRenewState) ?? .unknown
            } else if let cachedRenewState, let restored: RenewState = RenewState(rawValue: cachedRenewState) {
                // Reading the SDK's own cache back: the state it resolved when
                // it wrote the entry, so a locally calculated entitlement is
                // not re-derived into something it never claimed.
                renewState = restored
            } else {
                renewState = RenewState.derived(from: source)
            }

            let rawGrantType: String? = try? container.decodeIfPresent(String.self, forKey: .grantType)
            // Production default: everything the backend does not label
            // otherwise is a purchase.
            grantType = rawGrantType.flatMap { GrantType(rawValue: $0) } ?? .purchase

            renewsCount = (try? container.decodeIfPresent(Int.self, forKey: .renewsCount)) ?? 0
            lastActivatedOfferCode = try? container.decodeIfPresent(String.self, forKey: .lastActivatedOfferCode)
            trialStartDate = container.decodeTolerantDate(forKey: .trialStart)
            firstPurchaseDate = container.decodeTolerantDate(forKey: .firstPurchase)
            lastPurchaseDate = container.decodeTolerantDate(forKey: .lastPurchase)
            autoRenewDisableDate = container.decodeTolerantDate(forKey: .autoRenewDisable)
            transactions = (try? container.decodeIfPresent([StoreTransaction].self, forKey: .storeTransactions)) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(active, forKey: .active)
            try container.encode(source.rawValue, forKey: .source)
            try container.encodeIfPresent(startedDate, forKey: .started)
            try container.encodeIfPresent(expirationDate, forKey: .expires)
            // The wire shape is reproduced exactly: only the three real renew
            // states become a subscription object, and a non-renewable
            // entitlement has none at all.
            var subscription: EntitlementSubscription?
            if let renewStateValue: String = renewState.wireValue {
                subscription = EntitlementSubscription(renewState: renewStateValue)
            }
            if productId != nil || subscription != nil {
                let entitlementProduct = EntitlementProduct(productId: productId, subscription: subscription)
                try container.encode(entitlementProduct, forKey: .product)
            }
            // ...and the resolved state travels next to it under a key the API
            // never sends, so re-reading the cache yields the same state
            // instead of re-deriving one from the source.
            try container.encode(renewState.rawValue, forKey: .cachedRenewState)
            // The entitlements cache round-trips through Codable — everything
            // the SDK exposes has to survive it.
            try container.encode(grantType.rawValue, forKey: .grantType)
            try container.encode(renewsCount, forKey: .renewsCount)
            try container.encodeIfPresent(lastActivatedOfferCode, forKey: .lastActivatedOfferCode)
            try container.encodeIfPresent(trialStartDate, forKey: .trialStart)
            try container.encodeIfPresent(firstPurchaseDate, forKey: .firstPurchase)
            try container.encodeIfPresent(lastPurchaseDate, forKey: .lastPurchase)
            try container.encodeIfPresent(autoRenewDisableDate, forKey: .autoRenewDisable)
            if !transactions.isEmpty {
                try container.encode(transactions, forKey: .storeTransactions)
            }
        }

        private struct EntitlementProduct: Codable {
            let productId: String?
            var subscription: EntitlementSubscription?

            private enum CodingKeys: String, CodingKey {
                case productId = "product_id"
                case subscription
            }
        }

        private struct EntitlementSubscription: Codable {
            let renewState: String?

            private enum CodingKeys: String, CodingKey {
                case renewState = "renew_state"
            }
        }

        fileprivate enum CodingKeys: String, CodingKey {
            case id
            case active = "is_active"
            case source
            case started = "started_at"
            case expires = "expires_at"
            case product
            case grantType = "grant_type"
            case renewsCount = "renews_count"
            case lastActivatedOfferCode = "last_activated_offer_code"
            case trialStart = "trial_start_timestamp"
            case firstPurchase = "first_purchase_timestamp"
            case lastPurchase = "last_purchase_timestamp"
            case autoRenewDisable = "auto_renew_disable_timestamp"
            case storeTransactions = "store_transactions"
            /// Cache-private, in both directions. The API never sends it: it
            /// carries the renew state the SDK resolved, which the wire shape
            /// alone cannot express.
            ///
            /// It structurally cannot leak into a request either — entitlements
            /// are never part of a request body, and every body the SDK sends
            /// is built as a dictionary and serialized with JSONSerialization
            /// (`Request.httpBody`), not by encoding a Codable entity. The only
            /// consumer of this key is the entitlements cache in LocalStorage.
            case cachedRenewState = "sdk_renew_state"
        }
    }

    struct EntitlementsList: Decodable {
        let data: [Qonversion.Entitlement]

        init(from decoder: Decoder) throws {
            // Production tolerance: one malformed element degrades, it does
            // not null the user's whole access list.
            var container = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .data)
            data = try LossyArray.decode(Qonversion.Entitlement.self, from: &container)
        }

        private enum CodingKeys: String, CodingKey {
            case data
        }
    }
}

fileprivate extension KeyedDecodingContainer {

    /// The key names of these date fields are inherited from the previous API
    /// generation, where the values were unix timestamps; the current one
    /// sends ISO8601 strings. Both decode, and neither can fail the entitlement.
    func decodeTolerantDate(forKey key: Key) -> Date? {
        if let date: Date = try? decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        if let timestamp: Double = try? decodeIfPresent(Double.self, forKey: key), timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }
}
