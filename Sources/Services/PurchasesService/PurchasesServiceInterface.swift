//
//  PurchasesServiceInterface.swift
//  Qonversion
//

import Foundation

protocol PurchasesServiceInterface {

    /// Reports the purchase to the backend; the transaction's jws proof is
    /// included as part of the payload.
    func send(_ transaction: Qonversion.Transaction, userId: String) async throws
}
