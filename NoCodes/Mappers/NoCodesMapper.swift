//
//  NoCodesMapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
import Qonversion

final class NoCodesMapper: NoCodesMapperInterface {
  func map(rawAction: [String: Any]) -> NoCodes.Action {
    let types: [String: NoCodes.ActionType] = [
      "url": .url,
      "deeplink": .deeplink,
      "navigation": .navigation,
      "makePurchase": .purchase,
      "restore": .restore,
      "close": .close,
      "closeAll": .closeAll,
      "getProducts": .loadProducts
    ]
    
    let data: [String: Any] = rawAction["data"] as? [String: Any] ?? [:]
    let rawActionType = data["type"] as? String ?? ""
    let type: NoCodes.ActionType = types[rawActionType] ?? .unknown
    let parameters: [String: Any] = data["parameters"] as? [String: Any] ?? [:]
    
    return NoCodes.Action(type:type, parameters:parameters)
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
    case .freeTrial: return "freeTrial"
    case .payUpFront: return "payUpFront"
    case .payAsYouGo: return "payAsYouGo"
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
        productInfo["currencySymbol"] = skProduct.priceLocale.currencySymbol
        productInfo["currency"] = skProduct.prettyCurrency
        
        if let subscriptionPeriod: SKProductSubscriptionPeriod = skProduct.subscriptionPeriod {
          productInfo["duration"] = map(periodUnit: subscriptionPeriod.unit)
          productInfo["numberOfUnits"] = subscriptionPeriod.numberOfUnits
        }
        
        if let introPrice: SKProductDiscount = skProduct.introductoryPrice {
          productInfo["introPrice"] = introPrice.price
          productInfo["introPriceType"] = map(introPriceType: introPrice.type)
          productInfo["introPricePaymentMode"] = map(introPricePaymentType: introPrice.paymentMode)
          productInfo["introPeriodUnit"] = map(periodUnit: introPrice.subscriptionPeriod.unit)
          productInfo["introPeriodNumberOfUnits"] = introPrice.subscriptionPeriod.numberOfUnits
          productInfo["introNumberOfPeriods"] = introPrice.numberOfPeriods
        }
      }
      
      productsInfo[product.qonversionID] = productInfo
    }
    
    return ["data": productsInfo]
  }
  
}
