//
//  QonversionPurchasesHandler.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 16.06.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
import Qonversion

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public class QonversionPurchasesHandler {
  
  public static func handle(transaction: Transaction) {
    Task.init {
      let products: [Product] = try await Product.products(for: Set([transaction.productID]))
      
      guard let product: Product = products.first else { return }
      
      let tempDict = try? JSONSerialization.jsonObject(with: product.jsonRepresentation, options: [])
      let jsonDict = tempDict as? [String: Any] ?? [:]
      let attributes = jsonDict["attributes"] as? [String: Any]
        
      guard let offers = attributes?["offers"] as? [[String: Any]],
            let currencyCode: String = offers.first?["currencyCode"] as? String
      else { return }

      let purchaseInfo = QNPurchaseInfo()
      purchaseInfo.productId = product.id
      purchaseInfo.price = "\(product.price)"
      purchaseInfo.currency = currencyCode
      purchaseInfo.transactionId = String(transaction.id)
      purchaseInfo.originalTransactionId = String(transaction.originalID)
      
      if let subscriptionInfo: Product.SubscriptionInfo = product.subscription {
        purchaseInfo.subscriptionPeriodUnit = convert(periodUnit: subscriptionInfo.subscriptionPeriod.unit)
        purchaseInfo.subscriptionPeriodNumberOfUnits = String(subscriptionInfo.subscriptionPeriod.value)
  
        if let introductoryOffer: Product.SubscriptionOffer = subscriptionInfo.introductoryOffer {
          purchaseInfo.introductoryPrice = "\(introductoryOffer.price)"
          purchaseInfo.introductoryNumberOfPeriods = String(introductoryOffer.periodCount)
          purchaseInfo.introductoryPeriodUnit = convert(periodUnit: introductoryOffer.period.unit)
          purchaseInfo.introductoryPeriodNumberOfUnits = String(introductoryOffer.period.value)
          purchaseInfo.introductoryPaymentMode = convert(paymentMode: introductoryOffer.paymentMode)
          purchaseInfo.storefrontCountryCode = await Storefront.current?.countryCode
        }
      }
      
      Qonversion.handlePurchase(purchaseInfo)
    }
  }
  
  private static func convert(paymentMode: Product.SubscriptionOffer.PaymentMode) -> String {
    var result = -1
    switch paymentMode {
    case .payAsYouGo:
      result = 0
    case .payUpFront:
      result = 1
    case .freeTrial:
      result = 2
    default:
      result = -1
    }
    
    return String(result)
  }
  
  private static func convert(periodUnit: Product.SubscriptionPeriod.Unit) -> String {
    var result = -1
    switch periodUnit {
    case .day:
      result = 0
    case .week:
      result = 1
    case .month:
      result = 2
    case .year:
      result = 3
      
    @unknown default:
      result = -1
    }
    
    return String(result)
  }
  
}
