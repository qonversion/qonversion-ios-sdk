//
//  NoCodesAction.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

/// Type of the action
public enum NoCodesActionType {
  /// Unspecified action type
  case unknown
  
  /// URL action that opens the URL using SafariViewController
  case url
  
  /// Deeplink action that opens if Application can open specified deeplink
  case deeplink
  
  /// Navigation to another NoCodes screen
  case navigation
  
  /// Purchase the product
  case purchase
  
  /// Restore all purchases
  case restore
  
  /// Close current screen
  case close
  
  /// Close all NoCodes screens
  case closeAll
  
  /// Internal action for store products loading
  case loadProducts
  
  /// Internal action that indicates that the screen is ready to be shown
  case showScreen
}

/// Action performed in the NoCodes
public struct NoCodesAction {
  /// Type of the action
  public let type: NoCodesActionType
  
  // Parameters for the action
  public let parameters: [String: Any]?
}

#endif 