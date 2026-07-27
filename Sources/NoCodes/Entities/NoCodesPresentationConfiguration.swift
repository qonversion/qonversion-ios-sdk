//
//  NoCodesPresentationConfiguration.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

/// NoCodesPresentationStyle enum from No-Codes module
public enum NoCodesPresentationStyle: Sendable {
  case popover
  case push
  case fullScreen
}

/// PresentationConfiguration type from No-Codes module
public struct NoCodesPresentationConfiguration: Sendable {
  let animated: Bool
  let presentationStyle: NoCodesPresentationStyle
  let statusBarHidden: Bool
  
  public init(animated: Bool, presentationStyle: NoCodesPresentationStyle, statusBarHidden: Bool = false) {
    self.animated = animated
    self.presentationStyle = presentationStyle
    self.statusBarHidden = statusBarHidden
  }
  
  public static func defaultConfiguration() -> NoCodesPresentationConfiguration {
    return NoCodesPresentationConfiguration(animated: true, presentationStyle: .fullScreen)
  }
}
