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
      // The typed `transaction.commitmentInfo` (StoreKit, iOS 26.4+) is not in the build SDK yet
      // (CI builds against Xcode 26.2), so we read the commitment block out of
      // `transaction.jsonRepresentation`, which follows the App Store Server API transaction schema.
      // Swap to the typed property once the build SDK reaches iOS 26.4.
      purchaseInfo.commitmentInfo = parseCommitmentInfo(from: transaction.jsonRepresentation)
    }

    return purchaseInfo
  }

  /// Parses Apple's `commitmentInfo` block out of `Transaction.jsonRepresentation`.
  ///
  /// Keys and encodings are verified against Apple's `app-store-server-library`
  /// `TransactionCommitmentInfo` model and its `signedTransaction.json` fixture:
  /// - `commitmentPrice` is an `Int64` in milliunits of the currency (e.g. 119880 -> 119.88) and is
  ///   the price of the whole commitment, not a single billing period.
  /// - `commitmentExpiresDate` is epoch milliseconds and marks when the whole commitment ends.
  /// The block is absent on pre-26.4 OSes, so this returns nil there.
  ///
  /// Intentionally not gated on iOS 26.4: the decode is pure JSON and stays testable on any OS.
  /// Only the call site that assigns to the availability-gated `commitmentInfo` property is gated.
  func parseCommitmentInfo(from jsonRepresentation: Data) -> Qonversion.TransactionCommitmentInfo? {
    guard let envelope = try? JSONDecoder().decode(TransactionEnvelope.self, from: jsonRepresentation),
          let info = envelope.commitmentInfo
    else { return nil }

    let commitmentPrice = NSDecimalNumber(value: info.commitmentPrice).dividing(by: NSDecimalNumber(value: 1000))
    let commitmentExpirationDate = Date(timeIntervalSince1970: info.commitmentExpiresDate / 1000.0)

    return Qonversion.TransactionCommitmentInfo(
      billingPeriodNumber: UInt(info.billingPeriodNumber),
      totalBillingPeriods: UInt(info.totalBillingPeriods),
      commitmentPrice: commitmentPrice,
      commitmentExpirationDate: commitmentExpirationDate
    )
  }

  private struct TransactionEnvelope: Decodable {
    let commitmentInfo: CommitmentInfoJSON?
  }

  /// Mirrors Apple's `TransactionCommitmentInfo` JSON (App Store Server API schema).
  /// `commitmentPrice` is in milliunits of the currency; `commitmentExpiresDate` is epoch milliseconds.
  private struct CommitmentInfoJSON: Decodable {
    let billingPeriodNumber: Int
    let totalBillingPeriods: Int
    let commitmentPrice: Int64
    let commitmentExpiresDate: Double
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
