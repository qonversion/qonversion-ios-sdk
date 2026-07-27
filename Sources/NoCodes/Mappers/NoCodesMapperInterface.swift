//
//  NoCodesMapperInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import Qonversion

protocol NoCodesMapperInterface: Sendable {

  func map(rawAction: [String: Any]) -> NoCodesAction
  func map(introPriceType: Qonversion.Product.SubscriptionOffer.OfferType) -> String
  func map(introPricePaymentType: Qonversion.Product.SubscriptionOffer.PaymentMode) -> String
  func map(periodUnit: Qonversion.Product.SubscriptionPeriod.Unit) -> String
  func map(products: [String: Qonversion.Product]) -> [String: Any]

}
