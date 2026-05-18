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
      purchaseInfo.commitmentInfo = parseCommitmentInfo(from: transaction.jsonRepresentation)
    }

    return purchaseInfo
  }

  @available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
  func parseCommitmentInfo(from jsonRepresentation: Data) -> Qonversion.TransactionCommitmentInfo? {
    // Decode straight from raw JSON bytes so that `price` is parsed as a Swift Decimal
    // without round-tripping through Double, and so `billingPeriodNumber` /
    // `totalBillingPeriods` survive whether Apple emits them as JSON ints or floats.
    guard let envelope = try? JSONDecoder().decode(TransactionEnvelope.self, from: jsonRepresentation),
          let info = envelope.commitmentInfo
    else { return nil }

    return Qonversion.TransactionCommitmentInfo(
      billingPeriodNumber: UInt(info.billingPeriodNumber),
      totalBillingPeriods: UInt(info.totalBillingPeriods),
      pricePerBillingPeriod: NSDecimalNumber(decimal: info.price),
      currentBillingPeriodExpirationDate: info.expirationDate
    )
  }

  @available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
  private struct TransactionEnvelope: Decodable {
    let commitmentInfo: CommitmentInfoJSON?
  }

  @available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
  private struct CommitmentInfoJSON: Decodable {
    let billingPeriodNumber: UInt64
    let totalBillingPeriods: UInt64
    let price: Decimal
    let expirationDate: Date

    enum CodingKeys: String, CodingKey {
      case billingPeriodNumber
      case totalBillingPeriods
      case price
      case expirationDate
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      billingPeriodNumber = try container.decode(UInt64.self, forKey: .billingPeriodNumber)
      totalBillingPeriods = try container.decode(UInt64.self, forKey: .totalBillingPeriods)
      price = try container.decode(Decimal.self, forKey: .price)
      expirationDate = try Self.decodeExpirationDate(from: container)
    }

    // Apple has not yet published the JSON encoding of Transaction.CommitmentInfo.expirationDate
    // in jsonRepresentation. Other Transaction date fields (purchaseDate, expiresDate,
    // signedDate) are Unix milliseconds, so we expect a number, but accept ISO-8601 and
    // numeric strings defensively. Swap to typed transaction.commitmentInfo?.expirationDate
    // and delete these fallbacks once the iOS 26.4 SDK ships.
    private static func decodeExpirationDate(
      from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
      if let millis = try? container.decode(Double.self, forKey: .expirationDate) {
        return Date(timeIntervalSince1970: millis / 1000.0)
      }

      let raw = try container.decode(String.self, forKey: .expirationDate)
      if let date = ISO8601DateFormatter().date(from: raw) {
        return date
      }
      if let millis = Double(raw) {
        return Date(timeIntervalSince1970: millis / 1000.0)
      }

      throw DecodingError.dataCorruptedError(
        forKey: .expirationDate, in: container,
        debugDescription: "Unrecognized expirationDate encoding: \(raw)"
      )
    }
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
