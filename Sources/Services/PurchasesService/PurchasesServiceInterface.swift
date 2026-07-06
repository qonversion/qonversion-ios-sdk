//
//  PurchasesServiceInterface.swift
//  Qonversion
//

import Foundation

protocol PurchasesServiceInterface {

    /// Reports the purchase to the backend: POST v3/users/{uid}/purchases.
    /// The transaction's jws proof travels in app_store_data.receipt.
    func send(_ transaction: Qonversion.Transaction, userId: String) async throws
}
