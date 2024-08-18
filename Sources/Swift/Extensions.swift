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
  
}
