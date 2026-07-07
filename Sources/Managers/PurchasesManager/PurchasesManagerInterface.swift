//
//  PurchasesManagerInterface.swift
//  Qonversion
//

import Foundation
import StoreKit

protocol PurchasesManagerInterface {

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

    /// Starts consuming out-of-band transaction updates (renewals, refunds,
    /// Ask to Buy approvals): each update is reported to the backend and is
    /// NEVER finished by the SDK.
    func startObservingTransactions()

    /// Reports purchases made by the host app (Analytics mode ingestion).
    /// Verified transactions are reported through the dedup gate and are
    /// NEVER finished — the host app owns their lifecycle.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func handle(purchasedTransactions: [VerificationResult<StoreKit.Transaction>]) async

    /// Domain-typed core of the ingestion above.
    func handle(transactions: [Qonversion.Transaction]) async

    /// Re-reports transactions left unfinished by previous sessions and
    /// finishes them after the backend confirms. Does nothing in Analytics
    /// mode, where the host app owns the transaction lifecycle. Deduplicated
    /// against the transaction updates listener.
    func processUnfinishedTransactions() async
}

extension PurchasesManagerInterface {

    @discardableResult
    func purchase(_ product: Qonversion.Product) async throws -> Qonversion.PurchaseResult {
        try await purchase(product, options: nil)
    }
}
