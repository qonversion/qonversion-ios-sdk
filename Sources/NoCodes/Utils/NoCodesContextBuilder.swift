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
#endif

/// The resolved appearance of a screen, already collapsed from
/// ``NoCodesTheme`` plus the environment. Kept as a plain value so the whole
/// context payload can be built and tested without UIKit.
enum NoCodesResolvedTheme: String {
  case light
  case dark
}

protocol NoCodesContextBuilderInterface {
  func buildContextJSON(resolvedTheme: NoCodesResolvedTheme, activeEntitlementIds: [String], productsContext: [String: Any], userProperties: [String: String]) -> String?
  func resolveIsFirstLaunch() -> Bool
  func calculateDaysSinceInstall() -> Int
}

extension NoCodesContextBuilderInterface {
  func buildContextJSON(resolvedTheme: NoCodesResolvedTheme, activeEntitlementIds: [String], productsContext: [String: Any]) -> String? {
    return buildContextJSON(resolvedTheme: resolvedTheme, activeEntitlementIds: activeEntitlementIds, productsContext: productsContext, userProperties: [:])
  }
}

final class NoCodesContextBuilder: NoCodesContextBuilderInterface {

  private static let alreadyLaunchedKey = "io.qonversion.nocodes.alreadyLaunchedBefore"

  func buildContextJSON(resolvedTheme: NoCodesResolvedTheme, activeEntitlementIds: [String], productsContext: [String: Any], userProperties: [String: String] = [:]) -> String? {
    var device: [String: String] = [:]
    device["platform"] = PlatformConstants.name
    device["osVersion"] = PlatformConstants.osVersion

    if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
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

    device["theme"] = resolvedTheme.rawValue

    if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
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
    if !userProperties.isEmpty {
      user["properties"] = userProperties
    }

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

private enum PlatformConstants {

  static let name: String = {
    #if os(iOS)
    return "iOS"
    #elseif os(macOS)
    return "macOS"
    #elseif os(tvOS)
    return "tvOS"
    #elseif os(watchOS)
    return "watchOS"
    #else
    return "unknown"
    #endif
  }()

  static let osVersion: String = {
    #if os(iOS)
    return UIDevice.current.systemVersion
    #else
    let version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    #endif
  }()
}

#if os(iOS)

extension NoCodesTheme {

  /// The interface style the screen should render with: `.auto` follows the
  /// presenting environment, the explicit modes override it.
  func resolveInterfaceStyle(traitCollection: UITraitCollection) -> UIUserInterfaceStyle {
    switch self {
    case .auto:
      return traitCollection.userInterfaceStyle
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }

  func resolveTheme(traitCollection: UITraitCollection) -> NoCodesResolvedTheme {
    let style: UIUserInterfaceStyle = resolveInterfaceStyle(traitCollection: traitCollection)

    return style == .dark ? .dark : .light
  }
}

#endif
