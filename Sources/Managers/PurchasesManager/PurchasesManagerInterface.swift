//
//  PurchasesManagerInterface.swift
//  Qonversion
//

import Foundation
import StoreKit

protocol PurchasesManagerInterface: AnyObject {

    /// A stream of purchases the SDK processed out of band (Ask to Buy / SCA
    /// approvals, renewals, refunds, purchases on other devices), in both
    /// launch modes. Every call returns an independent stream, and every
    /// purchase is delivered exactly once: broadcast to whoever is listening
    /// when it happens, otherwise kept — with no deadline — for the next
    /// stream alone.
    func deferredPurchases() -> AsyncStream<Qonversion.DeferredPurchase>

    /// The entitlements-only projection of ``deferredPurchases()``, plus the
    /// revocations no deferred purchase can carry. Every call returns an
    /// independent stream; the snapshot stays readable by streams created
    /// later, and reading it never consumes a deferred purchase.
    func entitlementsUpdates() -> AsyncStream<[String: Qonversion.Entitlement]>

    /// A stream of App Store promoted-purchase intents; call purchase() on an
    /// intent to proceed. Every call returns an independent stream, and an
    /// intent waiting for a subscriber is handed to exactly one of them.
    func promoPurchaseIntents() -> AsyncStream<Qonversion.PromoPurchaseIntent>

    /// Buys the product through the store, reports the purchase to the backend
    /// (through the user gate) and finishes the transaction only after the
    /// backend confirms. Returns the verified transaction.
    @discardableResult
    func purchase(_ product: Qonversion.Product, options: Qonversion.PurchaseOptions?) async throws -> Qonversion.PurchaseResult

    /// Restores the user's purchases: syncs with the store, reports the
    /// latest transaction of every product and returns the entitlements.
    /// When the backend is unreachable, entitlements are calculated locally.
    @discardableResult
    func restore() async throws -> [String: Qonversion.Entitlement]

    /// Requests a backend-signed promotional offer for the product's discount;
    /// pass the result via ``Qonversion/Qonversion/PurchaseOptions/promoOffer``,
    /// together with the app account token the signature was requested with.
    func promotionalOffer(for product: Qonversion.Product, discountId: String, appAccountToken: UUID?) async throws -> Qonversion.PromotionalOffer

    /// Starts consuming out-of-band transaction updates (renewals, refunds,
    /// Ask to Buy approvals): each update is reported to the backend and is
    /// NEVER finished by the SDK.
    func startObservingTransactions()

    #if os(iOS) || os(visionOS)
    /// Presents the system App Store offer code redemption sheet.
    func presentCodeRedemptionSheet()

    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
    #endif

    #if os(visionOS)
    /// The scene the visionOS purchase sheet is confirmed in.
    @MainActor
    func setPurchaseConfirmationScene(_ scene: UIScene?)
    #endif

    /// Reports purchases made by the host app (Analytics mode ingestion).
    /// Verified transactions are reported through the dedup gate and are
    /// NEVER finished — the host app owns their lifecycle.
    @discardableResult
    func handle(purchasedTransactions: [VerificationResult<StoreKit.Transaction>]) async -> Bool

    /// Domain-typed core of the ingestion above.
    @discardableResult
    func handle(transactions: [Qonversion.Transaction]) async -> Bool

    /// Reports the historical store transactions (latest per product) to the
    /// backend once per install. Never finishes them and never triggers the
    /// App Store sign-in prompt.
    @discardableResult
    func syncHistoricalData() async -> Bool

    /// Re-reports transactions left unfinished by previous sessions and
    /// finishes them after the backend confirms; in Analytics mode they are
    /// reported but never finished — the host app owns the transaction
    /// lifecycle. Deduplicated against the transaction updates listener.
    func processUnfinishedTransactions() async
}

extension PurchasesManagerInterface {

    @discardableResult
    func purchase(_ product: Qonversion.Product) async throws -> Qonversion.PurchaseResult {
        try await purchase(product, options: nil)
    }

    func promotionalOffer(for product: Qonversion.Product, discountId: String) async throws -> Qonversion.PromotionalOffer {
        try await promotionalOffer(for: product, discountId: discountId, appAccountToken: nil)
    }
}
