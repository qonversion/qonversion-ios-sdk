//
//  PurchasesServiceInterface.swift
//  Qonversion
//

import Foundation

protocol PurchasesServiceInterface {

    /// Reports the purchase to the backend; the transaction's jws proof is
    /// included as part of the payload. Association options (contextKeys,
    /// screenUid), when given, are attached to the report. Returns the
    /// resolved owner of the transaction when the backend provides one.
    @discardableResult
    func send(_ transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?, trigger: RequestTrigger) async throws -> String?

    /// Requests a backend-signed promotional offer for the store product. The
    /// app account token becomes part of the signed payload, so it must be the
    /// one the purchase is made with.
    func promotionalOffer(userId: String, offerId: String, productStoreId: String, appAccountToken: UUID?) async throws -> Qonversion.PromotionalOffer
}

extension PurchasesServiceInterface {

    func promotionalOffer(userId: String, offerId: String, productStoreId: String) async throws -> Qonversion.PromotionalOffer {
        try await promotionalOffer(userId: userId, offerId: offerId, productStoreId: productStoreId, appAccountToken: nil)
    }

    @discardableResult
    func send(_ transaction: Qonversion.Transaction, userId: String, trigger: RequestTrigger) async throws -> String? {
        try await send(transaction, userId: userId, options: nil, trigger: trigger)
    }

    @discardableResult
    func send(_ transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?) async throws -> String? {
        try await send(transaction, userId: userId, options: options, trigger: .purchase)
    }

    @discardableResult
    func send(_ transaction: Qonversion.Transaction, userId: String) async throws -> String? {
        try await send(transaction, userId: userId, options: nil, trigger: .purchase)
    }
}
