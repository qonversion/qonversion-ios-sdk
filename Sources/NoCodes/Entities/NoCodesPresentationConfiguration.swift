//
//  NoCodesPresentationConfiguration.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

/// PresentationStyle enum from NoCodes module
public enum PresentationStyle {
  case popover
  case push
  case fullScreen
}

/// PresentationConfiguration type from NoCodes module
public struct NoCodesPresentationConfiguration {
  let animated: Bool
  let presentationStyle: PresentationStyle
  let statusBarHidden: Bool
  
  public init(animated: Bool, presentationStyle: PresentationStyle, statusBarHidden: Bool = false) {
    self.animated = animated
    self.presentationStyle = presentationStyle
    self.statusBarHidden = statusBarHidden
  }
  
  public static func defaultConfiguration() -> NoCodesPresentationConfiguration {
    return NoCodesPresentationConfiguration(animated: true, presentationStyle: .fullScreen)
  }
}

#endif 