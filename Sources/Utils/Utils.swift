//
//  Utils.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 15.02.2024.
//

import Foundation
import StoreKit

typealias Codable = Decodable & Encodable

enum InternalConstants: String {
    case storagePrefix = "io.qonversion.sdk.storage."
    case appVersionBundleKey = "CFBundleShortVersionString"
}

extension Bundle {
    static var appVersion: String? { main.infoDictionary?[InternalConstants.appVersionBundleKey.rawValue] as? String }
}

extension String {
    func toCurrencySymbol() -> String? {
        let locale: Locale? = Locale.availableIdentifiers.map { Locale(identifier: $0) }.first { $0.currencyCode == self }
        
        return locale?.currencySymbol
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension Locale.Currency {
    func currencySymbol() -> String? {
        let locale: Locale? = Locale.availableIdentifiers.map { Locale(identifier: $0) }.first { $0.currencyCode == identifier }
        
        return locale?.currencySymbol
    }
}

extension SKProduct {
    
    func displayPrice() -> String? {
        return format(price: price, priceLcale: priceLocale)
    }
    
}

extension SKProductDiscount {
    
    func displayPrice() -> String? {
        return format(price: price, priceLcale: priceLocale)
    }
    
}

private func format(price: NSDecimalNumber, priceLcale: Locale) -> String? {
    let formatter = NumberFormatter()
    formatter.formatterBehavior = .behavior10_4
    formatter.locale = priceLcale
    
    return formatter.string(for: price)
}
