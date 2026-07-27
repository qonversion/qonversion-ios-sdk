//
//  StoreKitWrapperDelegate.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.02.2024.
//

import Foundation
import StoreKit

// StoreKit's PurchaseIntent is declared unavailable on watchOS, tvOS and
// visionOS, so the whole promoted-purchase machinery is compiled out there.
// The public promo API stays present but inert — see
// PurchasesManager.promoPurchaseIntents().
#if !os(watchOS) && !os(tvOS) && !os(visionOS)
protocol StoreKitWrapperDelegate: AnyObject {

    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product)
}
#endif
