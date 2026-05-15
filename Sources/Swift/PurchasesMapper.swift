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

@available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, visionOS 1.0, *)
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
      }
    }
    
    if #available(iOS 17.2, macOS 14.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *) {
      if let offer: Transaction.Offer = transaction.offer, offer.type == .promotional, let offerId = offer.id, let promoOffer: Product.SubscriptionOffer = product.subscription?.promotionalOffers.first(where: {$0.id == offerId}) {
        purchaseInfo.promoOfferId = offerId
        purchaseInfo.promoOfferPrice = "\(promoOffer.price)"
        purchaseInfo.promoOfferNumberOfPeriods = String(promoOffer.periodCount)
        purchaseInfo.promoOfferPeriodUnit = convert(periodUnit: promoOffer.period.unit)
        purchaseInfo.promoOfferPeriodNumberOfUnits = String(promoOffer.period.value)
        purchaseInfo.promoOfferPaymentMode = convert(paymentMode: promoOffer.paymentMode)
        
      }
    }
    
    purchaseInfo.storefrontCountryCode = await Storefront.current?.countryCode

    if #available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *) {
      // Transitional: parse Transaction.CommitmentInfo from jsonRepresentation.
      // Swap for direct typed access (transaction.commitmentInfo?.billingPeriodNumber)
      // once Xcode ships with the iOS 26.4 SDK.
      purchaseInfo.commitmentInfo = parseCommitmentInfo(from: transaction)
    }

    return purchaseInfo
  }

  @available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
  private func parseCommitmentInfo(from transaction: Transaction) -> Qonversion.TransactionCommitmentInfo? {
    guard let jsonDict = (try? JSONSerialization.jsonObject(with: transaction.jsonRepresentation)) as? [String: Any],
          let raw = jsonDict["commitmentInfo"] as? [String: Any],
          let billingPeriodNumber = raw["billingPeriodNumber"] as? UInt64,
          let totalBillingPeriods = raw["totalBillingPeriods"] as? UInt64,
          let priceDecimal = decimalNumber(from: raw["price"]),
          let expirationDate = parseDate(from: raw["expirationDate"])
    else { return nil }

    return Qonversion.TransactionCommitmentInfo(
      billingPeriodNumber: UInt(billingPeriodNumber),
      totalBillingPeriods: UInt(totalBillingPeriods),
      pricePerBillingPeriod: priceDecimal,
      currentBillingPeriodExpirationDate: expirationDate
    )
  }

  private func decimalNumber(from value: Any?) -> NSDecimalNumber? {
    if let number = value as? NSNumber {
      return NSDecimalNumber(decimal: number.decimalValue)
    }
    if let string = value as? String, let decimal = Decimal(string: string) {
      return NSDecimalNumber(decimal: decimal)
    }
    return nil
  }

  private func parseDate(from value: Any?) -> Date? {
    // Transaction.jsonRepresentation typically encodes dates as Unix timestamps in milliseconds,
    // but ISO 8601 strings have been observed in some payloads. Try both before giving up.
    if let millis = value as? NSNumber {
      return Date(timeIntervalSince1970: millis.doubleValue / 1000.0)
    }
    if let string = value as? String {
      let isoFormatter = ISO8601DateFormatter()
      if let date = isoFormatter.date(from: string) {
        return date
      }
      if let millis = Double(string) {
        return Date(timeIntervalSince1970: millis / 1000.0)
      }
    }
    return nil
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
