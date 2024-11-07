//
//  Extensions.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 04.08.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

extension Qonversion.PurchaseOptions {
  
  public convenience init(quantity: Int = 1, contextKeys: [String]? = nil) {
    self.init()
    self.quantity = quantity
    self.contextKeys = contextKeys
  }
  
  @available(iOS 12.2, macOS 10.14.4, watchOS 6.2, visionOS 1.0, *)
  public convenience init(quantity: Int = 1, contextKeys: [String]? = nil, promoOffer: Qonversion.PromotionalOffer? = nil) {
    self.init()
    self.quantity = quantity
    self.contextKeys = contextKeys
    self.promoOffer = promoOffer
  }
  
}
