//
//  Entitlement.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// A user's access right to a feature, granted by a purchase or manually.
    public struct Entitlement: Codable {

        /// Qonversion entitlement identifier.
        public let id: String

        /// Whether the user currently has this entitlement.
        /// Note: active == true does not mean the subscription will renew.
        public let active: Bool

        /// Source of the purchase via which the entitlement was activated.
        public let source: Qonversion.Entitlement.Source

        /// Time at which the entitlement was started.
        public let startedDate: Date?

        /// Time at which the entitlement expires; nil for lifetime grants.
        public let expirationDate: Date?

        /// Qonversion product id that granted the entitlement.
        public let productId: String?

        public enum Source: String, Codable {
            case unknown
            case appStore = "appstore"
            case playStore = "playstore"
            case stripe
            case manual
        }

        init(
            id: String,
            active: Bool,
            source: Qonversion.Entitlement.Source,
            startedDate: Date? = nil,
            expirationDate: Date? = nil,
            productId: String? = nil
        ) {
            self.id = id
            self.active = active
            self.source = source
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

            let started = try container.decodeIfPresent(Int64.self, forKey: .started)
            startedDate = started.map { Date(timeIntervalSince1970: TimeInterval($0)) }

            // The backend sends expires == 0 for lifetime grants.
            let expires = try container.decodeIfPresent(Int64.self, forKey: .expires)
            expirationDate = (expires ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(expires!)) : nil

            let product = try container.decodeIfPresent(EntitlementProduct.self, forKey: .product)
            productId = product?.productId
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(active, forKey: .active)
            try container.encode(source.rawValue, forKey: .source)
            try container.encodeIfPresent(startedDate.map { Int64($0.timeIntervalSince1970) }, forKey: .started)
            try container.encodeIfPresent(expirationDate.map { Int64($0.timeIntervalSince1970) }, forKey: .expires)
            try container.encodeIfPresent(productId.map { EntitlementProduct(productId: $0) }, forKey: .product)
        }

        private struct EntitlementProduct: Codable {
            let productId: String

            private enum CodingKeys: String, CodingKey {
                case productId = "product_id"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id, active, source, started, expires, product
        }
    }

    struct EntitlementsList: Decodable {
        let data: [Qonversion.Entitlement]
    }
}
