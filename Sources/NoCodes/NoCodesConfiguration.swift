//
//  NoCodesConfiguration.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

/// Configuration struct from No-Codes module
public struct NoCodesConfiguration {
  /// Your project key from Qonversion Dashboard to setup the SDK
  public let projectKey: String
  
  /// Delegate
  public var delegate: NoCodesDelegate?
  
  /// Screen customization delegate
  public var screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?
  
  /// Purchase delegate. If provided, it will be used instead of the default Qonversion SDK purchase flow.
  public var purchaseDelegate: NoCodesPurchaseDelegate?
  
  /// Optional custom fallback file name. If not provided, defaults to "nocodes_fallbacks.json"
  public var fallbackFileName: String?
  
  /// Optional proxy URL for API requests. If not provided, uses default API endpoint
  public var proxyURL: String?
  
  /// Optional custom locale for No-Code screens localization.
  /// If set, this locale will take priority over the system default locale.
  /// The locale should be in standard format (e.g., "en", "en-US", "de", "de-DE").
  public var locale: String?
  
  /// Theme mode for No-Code screens.
  /// Controls how screens adapt to light/dark themes.
  /// Defaults to `.auto` which follows device settings.
  public var theme: NoCodesTheme
  
  /// Initializer of NoCodes Configuration.
  ///
  /// - Parameters:
  ///   - projectKey: Your project key from Qonversion Dashboard to setup the SDK
  ///   - delegate: delegate object.
  ///   - screenCustomizationDelegate: ``NoCodesScreenCustomizationDelegate`` screen customization delegate object.
  ///   - purchaseDelegate: ``NoCodesPurchaseDelegate`` purchase delegate object. If provided, it will be used instead of the default Qonversion SDK purchase flow.
  ///   - fallbackFileName: Optional custom fallback file name. If not provided, defaults to "nocodes_fallbacks.json"
  ///   - proxyURL: Optional proxy URL for API requests. If not provided, uses default API endpoint
  ///   - locale: Optional custom locale for No-Code screens localization. If not provided, uses system default
  ///   - theme: Theme mode for No-Code screens. Defaults to `.auto` which follows device settings
  public init(projectKey: String, delegate: NoCodesDelegate? = nil, screenCustomizationDelegate: NoCodesScreenCustomizationDelegate? = nil, purchaseDelegate: NoCodesPurchaseDelegate? = nil, fallbackFileName: String? = nil, proxyURL: String? = nil, locale: String? = nil, theme: NoCodesTheme = .auto) {
    self.projectKey = projectKey
    self.delegate = delegate
    self.screenCustomizationDelegate = screenCustomizationDelegate
    self.purchaseDelegate = purchaseDelegate
    self.fallbackFileName = fallbackFileName
    self.proxyURL = proxyURL
    self.locale = locale
    self.theme = theme
  }
  
}

#endif 