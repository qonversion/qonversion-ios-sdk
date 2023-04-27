//
//  PurchasesMapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

import Foundation
import StoreKit
@_exported import Qonversion

@available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
final class PurchasesMapper {
  func map(transactions: [Transaction], with products:[Product]) async -> [Qonversion.StoreKit2PurchaseModel] {
    var result: [Qonversion.StoreKit2PurchaseModel] = []
    for transaction in transactions {
      if let relatedProduct = products.first(where: { $0.id == transaction.productID }),
         let model = await map(transaction: transaction, with: relatedProduct) {
        result.append(model)
      }
    }
    
    return result
  }
  
  func map(transaction: Transaction, with product: Product) async -> Qonversion.StoreKit2PurchaseModel? {
    let tempDict = try? JSONSerialization.jsonObject(with: product.jsonRepresentation, options: [])
    let jsonDict = tempDict as? [String: Any] ?? [:]
    let attributes = jsonDict["attributes"] as? [String: Any]
    
    guard let offers = attributes?["offers"] as? [[String: Any]],
          let currencyCode: String = offers.first?["currencyCode"] as? String
    else { return nil }
    
    let purchaseInfo = Qonversion.StoreKit2PurchaseModel()
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
    
    return purchaseInfo
  }
  
  private func convert(paymentMode: Product.SubscriptionOffer.PaymentMode) -> String {
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
  
  private func convert(periodUnit: Product.SubscriptionPeriod.Unit) -> String {
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
