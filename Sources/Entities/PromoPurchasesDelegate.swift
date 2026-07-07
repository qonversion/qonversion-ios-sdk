//
//  PromoPurchasesDelegate.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// Decides whether the SDK should proceed with a purchase promoted in the
    /// App Store. Returning false (or having no delegate set) defers the
    /// purchase.
    public protocol PromoPurchasesDelegate: AnyObject {
        func shouldPurchasePromoProduct(id: String) async -> Bool
    }
}
