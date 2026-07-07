//
//  StoreKitFacadeDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.04.2024.
//

import Foundation
import StoreKit

protocol StoreKitFacadeDelegate: AnyObject {

    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product)

    /// A verified out-of-band transaction update (renewal, refund, Ask to Buy
    /// approval, purchase on another device). The facade never finishes these
    /// automatically — in Analytics mode the host app owns the transaction
    /// lifecycle; finishing is an explicit, mode-aware decision.
    func transactionUpdated(_ transaction: Qonversion.Transaction)
}

extension StoreKitFacadeDelegate {
    func transactionUpdated(_ transaction: Qonversion.Transaction) { }
}
