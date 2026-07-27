//
//  StoreKitMapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.02.2024.
//

import StoreKit

/// The boundary converter between StoreKit entities and Qonversion domain
/// models. Owns the conversion rules; the wrappers only invoke it at the
/// point where the StoreKit objects (and their verification envelopes)
/// are still in hand.
protocol StoreKitMapperInterface {

    func map(_ transaction: StoreKit.Transaction, jws: String?) -> Qonversion.Transaction
}
