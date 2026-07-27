//
//  NoCodesMapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import Qonversion

final class NoCodesMapper: NoCodesMapperInterface, Sendable {

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
      "showScreen": .showScreen,
      "redeemPromoCode": .redeemPromoCode,
      "screenAnalytics": .screenAnalytics,
      "getContext": .getContext,
      "purchaseLoaderPresent": .purchaseLoaderPresent,
      "custom": .custom
    ]

    let data: [String: Any] = rawAction["data"] as? [String: Any] ?? [:]
    let rawActionType: String = data["type"] as? String ?? ""
    let type: NoCodesActionType = types[rawActionType] ?? .unknown
    let parameters: [String: Any] = data["parameters"] as? [String: Any] ?? [:]

    return NoCodesAction(type: type, parameters: parameters)
  }

  func map(introPriceType: Qonversion.Product.SubscriptionOffer.OfferType) -> String {
    switch introPriceType {
    case .introductory: return "intro"
    case .promotional: return "promo"
    // The web builder only knows the two values above. A win-back offer is
    // never the product's introductory offer — the only slot this mapping
    // feeds — so it travels as "no known type" rather than as a fabricated
    // discount kind.
    case .winBack: return ""
    case .unknown: return ""
    }
  }

  func map(introPricePaymentType: Qonversion.Product.SubscriptionOffer.PaymentMode) -> String {
    switch introPricePaymentType {
    case .freeTrial: return "trial"
    case .payUpFront: return "pay_up_front"
    case .payAsYouGo: return "pay_as_you_go"
    case .unknown: return ""
    }
  }

  func map(periodUnit: Qonversion.Product.SubscriptionPeriod.Unit) -> String {
    switch periodUnit {
    case .day: return "day"
    case .week: return "week"
    case .month: return "month"
    case .year: return "year"
    case .unknown: return ""
    }
  }

  // The key set and the value types below are the contract the No-Codes web
  // builder reads: changing or dropping a key breaks rendered screens.
  func map(products: [String: Qonversion.Product]) -> [String: Any] {
    var productsInfo: [String: Any] = [:]

    products.values.forEach { product in
      var productInfo: [String: Any] = [:]
      productInfo["id"] = product.qonversionId
      productInfo["store_id"] = product.storeId

      // Everything below comes from the linked StoreKit product; without it
      // only the Qonversion identifiers are known.
      if product.isStoreProductLinked {
        productInfo["title"] = product.displayName
        // JSONSerialization only accepts NSNumber for numeric values.
        productInfo["price"] = product.price.map { NSDecimalNumber(decimal: $0) }
        productInfo["currency_symbol"] = currencySymbol(of: product)
        productInfo["currency_code"] = prettyCurrency(of: product)

        if let subscription: Qonversion.Product.SubscriptionInfo = product.subscription {
          productInfo["period_unit"] = map(periodUnit: subscription.subscriptionPeriod.unit)
          productInfo["period_unit_count"] = subscription.subscriptionPeriod.value

          if let introOffer: Qonversion.Product.SubscriptionOffer = subscription.introductoryOffer {
            productInfo["intro_price"] = NSDecimalNumber(decimal: introOffer.price)
            productInfo["intro_price_type"] = map(introPriceType: introOffer.type)
            productInfo["payment_mode"] = map(introPricePaymentType: introOffer.paymentMode)
            productInfo["intro_period_unit"] = map(periodUnit: introOffer.period.unit)
            productInfo["intro_period_unit_count"] = introOffer.period.value
            productInfo["intro_number_of_periods"] = introOffer.periodCount
          }
        }
      }

      productsInfo[product.qonversionId] = productInfo
    }

    return ["data": productsInfo]
  }
}

// MARK: - Private

extension NoCodesMapper {

  /// The ISO 4217 code of the store price currency — the StoreKit 2 equivalent
  /// of the `SKProduct.priceLocale.currencyCode` the previous SDK reported.
  private func prettyCurrency(of product: Qonversion.Product) -> String? {
    return product.priceFormatStyle?.currencyCode
  }

  /// The localized currency symbol of the store price. Before iOS 16 the price
  /// format style may carry a sentinel locale, so the ISO code is used as the
  /// fallback source of the symbol.
  private func currencySymbol(of product: Qonversion.Product) -> String? {
    guard let formatStyle: Decimal.FormatStyle.Currency = product.priceFormatStyle else { return nil }

    let localeSymbol: String? = formatStyle.locale.currencySymbol
    if let localeSymbol, !localeSymbol.isEmpty, localeSymbol != CurrencyConstants.placeholderSymbol {
      return localeSymbol
    }

    return formatStyle.currencyCode.toCurrencySymbol()
  }
}

private enum CurrencyConstants {
  /// The generic currency sign Foundation returns when the locale carries no
  /// real currency.
  static let placeholderSymbol = "\u{00A4}"
}
