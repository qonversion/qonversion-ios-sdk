//
//  NoCodesMapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
@_exported import Qonversion

#if os(iOS)

final class NoCodesMapper: NoCodesMapperInterface {
  func map(rawAction: [String: Any]) -> NoCodesAction {
    let types: [String: NoCodesActionType] = [
      "url": .url,
      "deeplink": .deeplink,
      "navigation": .navigation,
      "makePurchase": .purchase,
      "restore": .restore,
      "close": .close,
      "closeAll": .closeAll,
      "getProducts": .loadProducts,
      "showScreen": .showScreen
    ]
    
    let data: [String: Any] = rawAction["data"] as? [String: Any] ?? [:]
    let rawActionType = data["type"] as? String ?? ""
    let type: NoCodesActionType = types[rawActionType] ?? .unknown
    let parameters: [String: Any] = data["parameters"] as? [String: Any] ?? [:]
    
    return NoCodesAction(type:type, parameters:parameters)
  }
  
  func map(introPriceType: SKProductDiscount.`Type`) -> String {
    switch introPriceType {
    case .introductory: return "intro"
    case .subscription: return "promo"
    @unknown default: return ""
    }
  }
  
  func map(introPricePaymentType: SKProductDiscount.PaymentMode) -> String {
    switch introPricePaymentType {
    case .freeTrial: return "trial"
    case .payUpFront: return "pay_up_front"
    case .payAsYouGo: return "pay_as_you_go"
    @unknown default: return ""
    }
  }
  
  func map(periodUnit: SKProduct.PeriodUnit) -> String {
    switch periodUnit {
    case .day: return "day"
    case .week: return "week"
    case .month: return "month"
    case .year: return "year"
    @unknown default: return ""
    }
  }
  
  func map(products: [String: Qonversion.Product]) -> [String: Any] {
    var productsInfo: [String: Any] = [:]
    
    products.values.forEach { product in
      var productInfo: [String: Any] = [:]
      productInfo["id"] = product.qonversionID
      productInfo["store_id"] = product.storeID

      if let skProduct: SKProduct = product.skProduct {
        productInfo["title"] = skProduct.localizedTitle
        productInfo["price"] = skProduct.price
        productInfo["currency_symbol"] = skProduct.priceLocale.currencySymbol
        productInfo["currency_code"] = skProduct.prettyCurrency
        
        if let subscriptionPeriod: SKProductSubscriptionPeriod = skProduct.subscriptionPeriod {
          productInfo["period_unit"] = map(periodUnit: subscriptionPeriod.unit)
          productInfo["period_unit_count"] = subscriptionPeriod.numberOfUnits
        }
        
        if let introPrice: SKProductDiscount = skProduct.introductoryPrice {
          productInfo["intro_price"] = introPrice.price
          productInfo["intro_price_type"] = map(introPriceType: introPrice.type)
          productInfo["payment_mode"] = map(introPricePaymentType: introPrice.paymentMode)
          productInfo["intro_period_unit"] = map(periodUnit: introPrice.subscriptionPeriod.unit)
          productInfo["intro_period_unit_count"] = introPrice.subscriptionPeriod.numberOfUnits
          productInfo["intro_number_of_periods"] = introPrice.numberOfPeriods
        }
      }
      
      productsInfo[product.qonversionID] = productInfo
    }
    
    return ["data": productsInfo]
  }
  
}

#endif
