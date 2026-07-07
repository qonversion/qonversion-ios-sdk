//
//  PurchasesManagerInterface.swift
//  Qonversion
//

import Foundation

protocol PurchasesManagerInterface {

    /// Buys the product through the store, reports the purchase to the backend
    /// (through the user gate) and finishes the transaction only after the
    /// backend confirms. Returns the verified transaction.
    @discardableResult
    func purchase(_ product: Qonversion.Product) async throws -> Qonversion.PurchaseResult

    /// Restores the user's purchases: syncs with the store, reports the
    /// latest transaction of every product and returns the entitlements.
    /// When the backend is unreachable, entitlements are calculated locally.
    @discardableResult
    func restore() async throws -> [String: Qonversion.Entitlement]

    /// Starts consuming out-of-band transaction updates (renewals, refunds,
    /// Ask to Buy approvals): each update is reported to the backend and is
    /// NEVER finished by the SDK.
    func startObservingTransactions()
}
