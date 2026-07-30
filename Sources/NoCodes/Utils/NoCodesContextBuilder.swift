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

extension NoCodesTheme {

  /// The appearance a screen has to render with. A forced theme wins over the
  /// system one: a host that configured `.light` must stay light when the user
  /// flips the system appearance while the screen is open.
  func resolvedTheme(isSystemDark: Bool) -> NoCodesResolvedTheme {
    switch self {
    case .auto:
      return isSystemDark ? .dark : .light
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }
}

protocol NoCodesContextBuilderInterface: Sendable {
  func buildContextJSON(resolvedTheme: NoCodesResolvedTheme, activeEntitlementIds: [String], productsContext: [String: any Sendable], userProperties: [String: String]) -> String?
  func resolveIsFirstLaunch() -> Bool
  func calculateDaysSinceInstall() -> Int
}

extension NoCodesContextBuilderInterface {
  func buildContextJSON(resolvedTheme: NoCodesResolvedTheme, activeEntitlementIds: [String], productsContext: [String: any Sendable]) -> String? {
    return buildContextJSON(resolvedTheme: resolvedTheme, activeEntitlementIds: activeEntitlementIds, productsContext: productsContext, userProperties: [:])
  }
}

/// The "this install has launched before" flag, and the answer derived from it.
enum NoCodesFirstLaunch {

  // The production Objective-C SDK wrote this very key, so an upgraded install
  // keeps its answer instead of looking brand new.
  static let alreadyLaunchedKey = "io.qonversion.nocodes.alreadyLaunchedBefore"

  /// Latches the flag and answers whether this launch is the first one.
  /// Resolved once at SDK initialization: doing it per context build made the
  /// first screen ever shown the only one that could see `true`.
  static func resolve(storage: UserDefaults, daysSinceInstall: Int) -> Bool {
    if storage.bool(forKey: alreadyLaunchedKey) {
      return false
    }

    storage.set(true, forKey: alreadyLaunchedKey)

    // A missing flag on an app installed days ago is an install that simply
    // never reached this code, not a first launch.
    return daysSinceInstall == 0
  }

  static func daysSinceInstall() -> Int {
    guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
          let attrs = try? FileManager.default.attributesOfItem(atPath: docsURL.path),
          let creationDate = attrs[.creationDate] as? Date else {
      return 0
    }
    let interval = Date().timeIntervalSince(creationDate)

    return max(0, Int(interval / 86400))
  }
}

final class NoCodesContextBuilder: NoCodesContextBuilderInterface, Sendable {

  /// UIDevice is main-actor isolated, so the OS version is snapshotted at
  /// construction (the assemblies build the graph on the main actor).
  private let osVersion: String
  private let isFirstLaunch: Bool

  @MainActor
  init(isFirstLaunch: Bool) {
    self.isFirstLaunch = isFirstLaunch
    osVersion = PlatformConstants.currentOSVersion()
  }

  func buildContextJSON(resolvedTheme: NoCodesResolvedTheme, activeEntitlementIds: [String], productsContext: [String: any Sendable], userProperties: [String: String] = [:]) -> String? {
    var device: [String: String] = [:]
    device["platform"] = PlatformConstants.name
    device["osVersion"] = osVersion

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
    return isFirstLaunch
  }

  func calculateDaysSinceInstall() -> Int {
    return NoCodesFirstLaunch.daysSinceInstall()
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
    #elseif os(visionOS)
    return "visionOS"
    #else
    return "unknown"
    #endif
  }()

  @MainActor
  static func currentOSVersion() -> String {
    #if os(iOS)
    return UIDevice.current.systemVersion
    #else
    let version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    #endif
  }
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
    return resolvedTheme(isSystemDark: traitCollection.userInterfaceStyle == .dark)
  }
}

#endif
