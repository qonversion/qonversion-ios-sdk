//
//  StoreKitFacadeDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.04.2024.
//

import Foundation
import StoreKit

protocol StoreKitFacadeDelegate {
    
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product)
    
}
