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
  let projectKey: String
  
  /// Delegate
  let delegate: NoCodesDelegate?
  
  /// Screen customization delegate
  let screenCustomizationDelegate: NoCodesScreenCustomizationDelegate?
  
  /// Optional custom fallback file name. If not provided, defaults to "nocodes_fallbacks.json"
  let fallbackFileName: String?
  
  /// Initializer of NoCodes Configuration.
  ///
  /// - Parameters:
  ///   - projectKey: Your project key from Qonversion Dashboard to setup the SDK
  ///   - delegate: delegate object.
  ///   - screenCustomizationDelegate: ``NoCodesScreenCustomizationDelegate`` screen customization delegate object.
  ///   - fallbackFileName: Optional custom fallback file name. If not provided, defaults to "nocodes_fallbacks.json"
  public init(projectKey: String, delegate: NoCodesDelegate? = nil, screenCustomizationDelegate: NoCodesScreenCustomizationDelegate? = nil, fallbackFileName: String? = nil) {
    self.projectKey = projectKey
    self.delegate = delegate
    self.screenCustomizationDelegate = screenCustomizationDelegate
    self.fallbackFileName = fallbackFileName
  }
}

#endif 