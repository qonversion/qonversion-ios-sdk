//
//  StoreProductWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.04.2024.
//

import Foundation
import StoreKit

struct StoreProductWrapper {
    
    var id: String? {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *) {
            return product?.id
        } else {
            return oldProduct?.productIdentifier
        }
    }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    var product: StoreKit.Product? { _product as? StoreKit.Product }
    
    let oldProduct: SKProduct?
    
    private let _product: Any?
    
    init(_product: Any?, oldProduct: SKProduct?) {
        self._product = _product
        self.oldProduct = oldProduct
    }
    
}
