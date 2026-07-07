//
//  PurchasesServiceInterface.swift
//  Qonversion
//

import Foundation

protocol PurchasesServiceInterface {

    /// Reports the purchase to the backend; the transaction's jws proof is
    /// included as part of the payload. Association options (contextKeys,
    /// screenUid), when given, are attached to the report.
    func send(_ transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?) async throws

    /// Requests a backend-signed promotional offer for the store product.
    func promotionalOffer(userId: String, offerId: String, productStoreId: String) async throws -> Qonversion.PromotionalOffer
}

extension PurchasesServiceInterface {

    func send(_ transaction: Qonversion.Transaction, userId: String) async throws {
        try await send(transaction, userId: userId, options: nil)
    }
}
