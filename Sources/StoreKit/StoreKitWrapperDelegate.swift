//
//  StoreKitWrapperDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.02.2024.
//

import Foundation
import StoreKit

@available(iOS 15.0, *)
protocol StoreKitWrapperDelegate {
    
    func promoPurchaseIntent(product: Product)
    
}
