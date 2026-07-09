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

        public enum Source: String, Codable, Sendable {
            case unknown
            case appStore = "appstore"
            case playStore = "playstore"
            case stripe
            case manual
        }

        public enum RenewState: String, Codable, Sendable {
            case unknown
            case willRenew = "will_renew"
            case canceled
            case billingIssue = "billing_issue"
        }

        init(
            id: String,
            active: Bool,
            source: Qonversion.Entitlement.Source,
            renewState: Qonversion.Entitlement.RenewState = .unknown,
            startedDate: Date? = nil,
            expirationDate: Date? = nil,
            productId: String? = nil
        ) {
            self.id = id
            self.active = active
            self.source = source
            self.renewState = renewState
            self.startedDate = startedDate
            self.expirationDate = expirationDate
            self.productId = productId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            active = try container.decode(Bool.self, forKey: .active)

            let rawSource = try container.decodeIfPresent(String.self, forKey: .source)
            source = rawSource.flatMap { Source(rawValue: $0) } ?? .unknown

            startedDate = try container.decodeIfPresent(Date.self, forKey: .started)
            expirationDate = try container.decodeIfPresent(Date.self, forKey: .expires)

            let product = try container.decodeIfPresent(EntitlementProduct.self, forKey: .product)
            productId = product?.productId
            let rawRenewState = product?.subscription?.renewState
            renewState = rawRenewState.flatMap { RenewState(rawValue: $0) } ?? .unknown
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(active, forKey: .active)
            try container.encode(source.rawValue, forKey: .source)
            try container.encodeIfPresent(startedDate, forKey: .started)
            try container.encodeIfPresent(expirationDate, forKey: .expires)
            if productId != nil || renewState != .unknown {
                let subscription = renewState == .unknown ? nil : EntitlementSubscription(renewState: renewState.rawValue)
                try container.encode(EntitlementProduct(productId: productId ?? "", subscription: subscription), forKey: .product)
            }
        }

        private struct EntitlementProduct: Codable {
            let productId: String
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

        private enum CodingKeys: String, CodingKey {
            case id
            case active = "is_active"
            case source
            case started = "started_at"
            case expires = "expires_at"
            case product
        }
    }

    struct EntitlementsList: Decodable {
        let data: [Qonversion.Entitlement]
    }
}
