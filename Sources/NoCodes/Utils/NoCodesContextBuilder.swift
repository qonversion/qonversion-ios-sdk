//
//  NoCodesContextBuilder.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 12.03.2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit

protocol NoCodesContextBuilderInterface {
  func resolveInterfaceStyle(theme: NoCodesTheme, traitCollection: UITraitCollection) -> UIUserInterfaceStyle
  func buildContextJSON(theme: NoCodesTheme, traitCollection: UITraitCollection, activeEntitlementIds: [String], productsContext: [String: Any]) -> String?
  func resolveIsFirstLaunch() -> Bool
  func calculateDaysSinceInstall() -> Int
}

final class NoCodesContextBuilder: NoCodesContextBuilderInterface {

  private static let alreadyLaunchedKey = "io.qonversion.nocodes.alreadyLaunchedBefore"

  func resolveInterfaceStyle(theme: NoCodesTheme, traitCollection: UITraitCollection) -> UIUserInterfaceStyle {
    switch theme {
    case .auto:
      return traitCollection.userInterfaceStyle
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }

  func buildContextJSON(theme: NoCodesTheme, traitCollection: UITraitCollection, activeEntitlementIds: [String], productsContext: [String: Any]) -> String? {
    var device: [String: String] = [:]
    device["platform"] = "iOS"
    device["osVersion"] = UIDevice.current.systemVersion

    if #available(iOS 16, *) {
      if let lang = Locale.current.language.languageCode?.identifier {
        device["language"] = lang
      }
    } else {
      if let lang = Locale.current.languageCode {
        device["language"] = lang
      }
    }

    device["locale"] = Locale.current.identifier

    if let appVersion = Bundle.appVersion {
      device["appVersion"] = appVersion
    }

    let resolvedStyle = resolveInterfaceStyle(theme: theme, traitCollection: traitCollection)
    switch resolvedStyle {
    case .dark: device["theme"] = "dark"
    default: device["theme"] = "light"
    }

    if #available(iOS 16, *) {
      if let region = Locale.current.region?.identifier {
        device["country"] = region
      }
    } else {
      if let region = Locale.current.regionCode {
        device["country"] = region
      }
    }

    var user: [String: Any] = [:]
    user["isFirstLaunch"] = resolveIsFirstLaunch() ? "true" : "false"
    user["daysSinceInstall"] = calculateDaysSinceInstall()
    user["hasAnyEntitlement"] = activeEntitlementIds.isEmpty ? "false" : "true"
    user["entitlements"] = activeEntitlementIds

    var contextData: [String: Any] = ["device": device, "user": user]
    if !productsContext.isEmpty {
      contextData["products"] = productsContext
    }

    let wrapper: [String: Any] = ["data": contextData]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: wrapper),
          let jsString = String(data: jsonData, encoding: .utf8) else { return nil }

    return jsString
  }

  func resolveIsFirstLaunch() -> Bool {
    let daysSinceInstall = calculateDaysSinceInstall()
    if UserDefaults.standard.bool(forKey: Self.alreadyLaunchedKey) {
      return false
    }

    UserDefaults.standard.set(true, forKey: Self.alreadyLaunchedKey)
    return daysSinceInstall == 0
  }

  func calculateDaysSinceInstall() -> Int {
    guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
          let attrs = try? FileManager.default.attributesOfItem(atPath: docsURL.path),
          let creationDate = attrs[.creationDate] as? Date else {
      return 0
    }
    let interval = Date().timeIntervalSince(creationDate)
    return max(0, Int(interval / 86400))
  }
}

#endif
