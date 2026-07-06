//
//  StoreKitMapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.02.2024.
//

import StoreKit

class StoreKitMapper: StoreKitMapperInterface {

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func map(_ transaction: StoreKit.Transaction, jws: String?) -> Qonversion.Transaction {
        return Qonversion.Transaction(transaction: transaction, jws: jws)
    }

    func map(_ transaction: SKPaymentTransaction, product: SKProduct) -> Qonversion.Transaction {
        return Qonversion.Transaction(transaction: transaction, product: product)
    }
}
