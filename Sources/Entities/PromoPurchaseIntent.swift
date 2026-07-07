//
//  PromoPurchaseIntent.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// A purchase promoted in the App Store. Call ``purchase(options:)`` to
    /// proceed — immediately or whenever the app is ready (e.g. after
    /// onboarding); dropping the intent defers the purchase. The intent is
    /// one-shot: the second purchase() call throws.
    public struct PromoPurchaseIntent {

        private final class OneShotFlag {
            private let lock = NSLock()
            private var used = false

            /// True exactly once.
            func take() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !used else { return false }
                used = true
                return true
            }
        }

        /// The App Store product id of the promoted product.
        public let productId: String

        private let flag = OneShotFlag()
        private let purchaseHandler: (PurchaseOptions?) async throws -> PurchaseResult

        init(productId: String, purchaseHandler: @escaping (PurchaseOptions?) async throws -> PurchaseResult) {
            self.productId = productId
            self.purchaseHandler = purchaseHandler
        }

        /// Runs the regular purchase flow for the promoted product. One-shot.
        @discardableResult
        public func purchase(options: PurchaseOptions? = nil) async throws -> PurchaseResult {
            guard flag.take() else {
                throw QonversionError(type: .promoPurchaseIntentAlreadyHandled)
            }

            return try await purchaseHandler(options)
        }
    }
}
