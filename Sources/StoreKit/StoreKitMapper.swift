//
//  StoreKitMapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.02.2024.
//

import StoreKit

class StoreKitMapper: StoreKitMapperInterface {

    func map(_ transaction: StoreKit.Transaction, jws: String?) -> Qonversion.Transaction {
        return Qonversion.Transaction(transaction: transaction, jws: jws)
    }
}
