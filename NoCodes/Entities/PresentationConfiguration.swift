//
//  PresentationConfiguration.swift
//  QonversionNoCodes
//
//  Created by Suren Sarkisyan on 23.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

extension NoCodes {
  
  public enum PresentationStyle {
    case popover
    case push
    case fullScreen
  }
  
  public struct PresentationConfiguration {
    let animated: Bool
    let presentationStyle: NoCodes.PresentationStyle
    
    static func defaultConfiguration() -> PresentationConfiguration {
      return PresentationConfiguration(animated: true, presentationStyle: .fullScreen)
    }
  }
  
}
