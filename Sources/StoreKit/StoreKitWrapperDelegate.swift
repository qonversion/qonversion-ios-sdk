//
//  StoreKitWrapperDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.02.2024.
//

import Foundation
import StoreKit

protocol StoreKitWrapperDelegate: AnyObject {
    
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product)
}
