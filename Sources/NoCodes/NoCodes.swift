//
//  NoCodes.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 17.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

public final class NoCodes {
  
  // MARK: - Public
  
  /// Use this variable to get the current initialized instance of the Qonversion No-Codes SDK.
  /// Please, use the variable only after initializing the SDK.
  /// - Returns: the current initialized instance of the ``NoCodes/NoCodes`` SDK
  public static let shared = NoCodes()
  private var flowCoordinator: NoCodesFlowCoordinator? = nil
  
  /// Use this function to initialize the No-Codes SDK.
  /// - Parameters:
  ///   - configuration: ``NoCodesConfiguration`` data for the SDK configuration.
  /// - Returns: ``NoCodes`` instance of the SDK.
  @discardableResult
  public static func initialize(with configuration: NoCodesConfiguration) -> NoCodes {
    let assembly: NoCodesAssembly = NoCodesAssembly(configuration: configuration)
    NoCodes.shared.flowCoordinator = assembly.flowCoordinator()
    
    NoCodes.shared.flowCoordinator?.preloadScreens()
    
    return NoCodes.shared
  }
  
  /// Use this function to set the delegate that will report what is happening inside No-Codes, what actions are being executed/failed, and so on.
  /// - Parameters:
  ///   - delegate: ``NoCodesDelegate`` object.
  public func set(delegate: NoCodesDelegate) {
    flowCoordinator?.set(delegate: delegate)
  }
  
  /// Use this function to set the screen customization delegate.
  /// - Parameters:
  ///   - delegate: screen customization ``NoCodesScreenCustomizationDelegate`` object.
  public func set(screenCustomizationDelegate: NoCodesScreenCustomizationDelegate) {
    flowCoordinator?.set(screenCustomizationDelegate: screenCustomizationDelegate)
  }
  
  /// Use this function to set the purchase delegate.
  /// This delegate should be used if you want to handle purchases and restore operations on your end.
  /// If this delegate is provided, it will be used instead of the default Qonversion SDK purchase flow.
  /// You can also provide it during the initialization via ``NoCodesConfiguration/purchaseDelegate``.
  /// - Parameters:
  ///   - delegate: ``NoCodesPurchaseDelegate`` object responsible for handling purchases and restore operations.
  public func set(purchaseDelegate: NoCodesPurchaseDelegate) {
    flowCoordinator?.set(purchaseDelegate: purchaseDelegate)
  }
  
  /// Use this function to display the screen.
  /// - Parameters:
  ///   - id: the context key of the screen.
  @MainActor
  public func showScreen(withContextKey contextKey: String) {
    flowCoordinator?.showScreen(withContextKey: contextKey)
  }
  
  /// Use this function to display the screen.
  /// - Parameters:
  ///   - id: identifier of the screen.
  @available(*, deprecated, message: "Use showNoCode(withContextKey:) instead")
  @MainActor
  public func showScreen(with id: String) {
    flowCoordinator?.showScreen(with: id)
  }
  
  /// Use this function to close all ``No-Codes`` screens.
  public func close() {
    flowCoordinator?.close()
  }
  
  /// Set a custom locale for No-Code screens localization.
  /// If set, this locale will take priority over the system default locale when determining
  /// which localization to show on No-Code screens.
  /// The locale should be in standard format (e.g., "en", "en-US", "de", "de-DE").
  ///
  /// You may set locale both after No-Codes SDK initialization with this method
  /// and during initialization via ``NoCodesConfiguration/locale``.
  ///
  /// Pass nil to reset to system default locale.
  ///
  /// - Parameters:
  ///   - locale: the custom locale code, or nil to use system default.
  public func setLocale(_ locale: String?) {
    flowCoordinator?.setLocale(locale)
  }
  
  /// Set the theme mode for No-Code screens.
  /// Controls how screens adapt to light/dark themes.
  ///
  /// You may set the theme both after No-Codes SDK initialization with this method
  /// and during initialization via ``NoCodesConfiguration/theme``.
  ///
  /// - Parameters:
  ///   - theme: the desired theme mode. Use `.auto` to follow device settings,
  ///            `.light` to force light theme, or `.dark` to force dark theme.
  public func setTheme(_ theme: NoCodesTheme) {
    flowCoordinator?.setTheme(theme)
  }
  
}

#endif
