//
//  NoCodesMapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
import Qonversion

protocol NoCodesMapperInterface {
  
  func map(rawAction: [String: Any]) -> NoCodes.Action
  func map(introPriceType: SKProductDiscount.`Type`) -> String
  func map(introPricePaymentType: SKProductDiscount.PaymentMode) -> String
  func map(periodUnit: SKProduct.PeriodUnit) -> String
  func map(products: [String: Qonversion.Product]) -> [String: Any]
  
}
