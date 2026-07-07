//
//  PromoPurchaseIntent.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// A purchase promoted in the App Store. Call ``purchase(options:)`` to
    /// proceed — immediately or whenever the app is ready (e.g. after
    /// onboarding); dropping the intent defers the purchase.
    public struct PromoPurchaseIntent {

        /// The App Store product id of the promoted product.
        public let productId: String

        private let purchaseHandler: (PurchaseOptions?) async throws -> PurchaseResult

        init(productId: String, purchaseHandler: @escaping (PurchaseOptions?) async throws -> PurchaseResult) {
            self.productId = productId
            self.purchaseHandler = purchaseHandler
        }

        /// Runs the regular purchase flow for the promoted product.
        @discardableResult
        public func purchase(options: PurchaseOptions? = nil) async throws -> PurchaseResult {
            try await purchaseHandler(options)
        }
    }
}
