//
//  Delegate.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
#if os(iOS)
import UIKit
#endif

#if os(iOS)

/// Delegate protocol from No-Codes module
public protocol NoCodesDelegate {
  /// Return a source ViewController for navigation
  func controllerForNavigation() -> UIViewController?
  
  /// Called when No-Codes screen is shown
  /// - Parameters:
  ///   - id: Screen identifier
  func noCodesHasShownScreen(id: String)
  
  /// Called when No-Codes flow starts executing an action
  /// - Parameters:
  ///   - action: ``NoCodesAction``
  func noCodesStartsExecuting(action: NoCodesAction)
  
  /// Called when No-Codes flow fails to execute an action
  /// - Parameters:
  ///   - action: ``NoCodesAction``
  ///   - error: error details
  func noCodesFailedToExecute(action: NoCodesAction, error: Error?)
  
  /// Called when No-Codes flow finishes executing an action
  /// - Parameters:
  ///   - action: ``NoCodesAction``
  /// For example, if the user made a purchase then action.type == .purchase
  func noCodesFinishedExecuting(action: NoCodesAction)
  
  /// Called when No-Codes flow is finished and the No-Codes screen is closed
  func noCodesFinished()
  
  /// Called when No-Codes screen loading failed
  /// Don't forget to close the screen using `NoCodes.shared.close()`
  /// - Parameters:
  ///   - error: error details
  func noCodesFailedToLoadScreen(error: Error?)
}

/// NoCodesScreenCustomizationDelegate protocol from No-Codes module
public protocol NoCodesScreenCustomizationDelegate {
  /// The function should return the screen presentation configuration used to present the first screen in the chain.
  func presentationConfigurationForScreen(contextKey: String) -> NoCodesPresentationConfiguration
  
  /// The function should return the screen presentation configuration used to present the first screen in the chain.
  /// Consider displaying screens using context keys. If so, the delegate method with contextKey will be called.
  func presentationConfigurationForScreen(id: String) -> NoCodesPresentationConfiguration
  
  /// View for popover presentation style for iPad. A new popover will be presented from this view
  /// Used only for screenPresentationStyle == .popover for iPad.
  /// You can omit implementing this delegate function if you do not support iPad or do not use popover presentation style.
  func viewForPopoverPresentation() -> UIView?
}

// MARK: - Default Implementations

public extension NoCodesDelegate {
  func controllerForNavigation() -> UIViewController? {
    return nil
  }
  
  func noCodesHasShownScreen(id: String) {
    
  }
  
  func noCodesStartsExecuting(action: NoCodesAction) {
    
  }
  
  func noCodesFailedToExecute(action: NoCodesAction) {
    
  }
  
  func noCodesFinishedExecuting(action: NoCodesAction) {
    
  }
  
  func noCodesFinished() {
    
  }
  
  func noCodesFailedToLoadScreen(error: Error?) {
    
  }
}

public extension NoCodesScreenCustomizationDelegate {
  func presentationConfigurationForScreen(id: String) -> NoCodesPresentationConfiguration {
    return NoCodesPresentationConfiguration.defaultConfiguration()
  }
  
  func presentationConfigurationForScreen(contextKey: String) -> NoCodesPresentationConfiguration {
    return NoCodesPresentationConfiguration.defaultConfiguration()
  }
  
  func viewForPopoverPresentation() -> UIView? {
    return nil
  }
}

#endif 
