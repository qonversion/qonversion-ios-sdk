//
//  StoreProductWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.04.2024.
//

import Foundation
import StoreKit

/// A thin envelope around the StoreKit product: real StoreKit.Product values
/// cannot be constructed in unit tests, so the boundary stays mockable.
struct StoreProductWrapper {

    var id: String? { product?.id }

    let product: StoreKit.Product?

    init(product: StoreKit.Product?) {
        self.product = product
    }
}
