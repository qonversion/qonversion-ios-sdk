//
//  Utils.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 15.02.2024.
//

import Foundation

enum InternalConstants: String {
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
