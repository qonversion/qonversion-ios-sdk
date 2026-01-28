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
  
  /// Navigation to another No-Codes screen
  case navigation
  
  /// Purchase the product
  case purchase
  
  /// Restore all purchases
  case restore
  
  /// Close current screen
  case close
  
  /// Close all No-Codes screens
  case closeAll
  
  /// Internal action for store products loading
  case loadProducts
  
  /// Internal action that indicates that the screen is ready to be shown
  case showScreen
  
  /// Go to a specific page within the current screen
  case goToPage
}

/// Type of the success/failure action
public enum NoCodesSuccessFailureActionType: String {
  /// No action - stay on current screen
  case none
  
  /// Close current screen
  case close
  
  /// Close all No-Codes screens
  case closeAll
  
  /// Navigate to another screen
  case navigation
  
  /// Open URL
  case url
  
  /// Open deeplink
  case deeplink
  
  /// Go to a specific page within the current screen
  case goToPage
}

/// Represents a success or failure action with its optional value
public struct NoCodesSuccessFailureAction {
  /// Type of the action
  public let type: NoCodesSuccessFailureActionType
  
  /// Value for the action (e.g., URL, screen ID, deeplink, page ID)
  public let value: String?
  
  public init(type: NoCodesSuccessFailureActionType, value: String? = nil) {
    self.type = type
    self.value = value
  }
}

/// Action performed in the No-Codes
public struct NoCodesAction {
  /// Type of the action
  public let type: NoCodesActionType
  
  // Parameters for the action
  public let parameters: [String: Any]?
  
  /// Action to perform on success (for purchase/restore actions)
  public let successAction: NoCodesSuccessFailureAction?
  
  /// Action to perform on failure (for purchase/restore actions)
  public let failureAction: NoCodesSuccessFailureAction?
  
  public init(
    type: NoCodesActionType,
    parameters: [String: Any]? = nil,
    successAction: NoCodesSuccessFailureAction? = nil,
    failureAction: NoCodesSuccessFailureAction? = nil
  ) {
    self.type = type
    self.parameters = parameters
    self.successAction = successAction
    self.failureAction = failureAction
  }
}

#endif 