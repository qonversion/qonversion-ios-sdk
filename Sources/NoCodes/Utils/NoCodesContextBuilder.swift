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
  func buildContextScript(theme: NoCodesTheme, traitCollection: UITraitCollection) -> String
  func resolveInterfaceStyle(theme: NoCodesTheme, traitCollection: UITraitCollection) -> UIUserInterfaceStyle
}

final class NoCodesContextBuilder: NoCodesContextBuilderInterface {

  private static let alreadyLaunchedKey = "io.qonversion.nocodes.alreadyLaunchedBefore"

  func buildContextScript(theme: NoCodesTheme, traitCollection: UITraitCollection) -> String {
    var deviceFields: [String: String] = [:]

    deviceFields["platform"] = "iOS"
    deviceFields["osVersion"] = UIDevice.current.systemVersion

    if #available(iOS 16, *) {
      if let lang = Locale.current.language.languageCode?.identifier {
        deviceFields["language"] = lang
      }
    } else {
      if let lang = Locale.current.languageCode {
        deviceFields["language"] = lang
      }
    }

    let localeId = Locale.current.identifier
    if !localeId.isEmpty {
      deviceFields["locale"] = localeId
    }

    if let appVersion = Bundle.appVersion {
      deviceFields["appVersion"] = appVersion
    }

    if #available(iOS 16, *) {
      if let region = Locale.current.region?.identifier {
        deviceFields["country"] = region
      }
    } else {
      if let region = Locale.current.regionCode {
        deviceFields["country"] = region
      }
    }

    let resolvedStyle = resolveInterfaceStyle(theme: theme, traitCollection: traitCollection)
    switch resolvedStyle {
    case .dark:
      deviceFields["theme"] = "dark"
    case .light, .unspecified:
      deviceFields["theme"] = "light"
    @unknown default:
      deviceFields["theme"] = "light"
    }

    let fieldsJS = deviceFields.map { key, value in
      "\(key): \"\(value)\""
    }.joined(separator: ", ")

    let daysSinceInstall = calculateDaysSinceInstall()
    let isFirstLaunch = resolveIsFirstLaunch(daysSinceInstall: daysSinceInstall)

    let userFieldsJS = "isFirstLaunch: \(isFirstLaunch), daysSinceInstall: \(daysSinceInstall)"

    return "window.noCodesContext = { device: { \(fieldsJS) }, user: { \(userFieldsJS) } };"
  }

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

  // MARK: - Private

  private func resolveIsFirstLaunch(daysSinceInstall: Int) -> Bool {
    if UserDefaults.standard.bool(forKey: Self.alreadyLaunchedKey) {
      return false
    }

    UserDefaults.standard.set(true, forKey: Self.alreadyLaunchedKey)
    return daysSinceInstall == 0
  }

  private func calculateDaysSinceInstall() -> Int {
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
