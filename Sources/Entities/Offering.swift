//
//  Offering.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// The user's offerings — groups of products behind your paywalls,
    /// personalized by experiments.
    // @unchecked: immutable value; Product is @unchecked Sendable itself.
    public struct Offerings: @unchecked Sendable {

        /// The offering marked as main in the Qonversion Dashboard.
        public let main: Qonversion.Offering?

        /// All the offerings available to the user.
        public let availableOfferings: [Qonversion.Offering]

        /// Returns the offering with the given identifier, if it exists.
        public func offering(for identifier: String) -> Qonversion.Offering? {
            return availableOfferings.first { $0.id == identifier }
        }

        init(offerings: [Qonversion.Offering]) {
            availableOfferings = offerings
            main = offerings.first { $0.tag == .main }
        }
    }

    /// A group of products behind a paywall, in the order configured in the
    /// Qonversion Dashboard.
    // @unchecked: immutable value; Product is @unchecked Sendable itself.
    public struct Offering: Decodable, @unchecked Sendable {

        /// The unique Qonversion offering identifier.
        public let id: String

        /// The offering tag; `.main` marks the main offering.
        public let tag: Qonversion.Offering.Tag

        /// The offering products in the paywall order.
        public let products: [Qonversion.Product]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            // Unknown tag values from a newer backend must not fail the list.
            let tagValue: Int = try container.decodeIfPresent(Int.self, forKey: .tag) ?? 0
            tag = Qonversion.Offering.Tag(rawValue: tagValue) ?? .none
            products = try container.decodeIfPresent([Qonversion.Product].self, forKey: .products) ?? []
        }

        init(id: String, tag: Qonversion.Offering.Tag, products: [Qonversion.Product]) {
            self.id = id
            self.tag = tag
            self.products = products
        }

        /// The type of the offering.
        public enum Tag: Int, Sendable {

            /// A regular offering.
            case none = 0

            /// The main offering of the project.
            case main = 1
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case tag
            case products
        }
    }
}
