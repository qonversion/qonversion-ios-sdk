//
//  StoreKitWrapperDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.02.2024.
//

import Foundation
import StoreKit

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
protocol StoreKitWrapperDelegate {
    
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product)
    
}
