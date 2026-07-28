//
//  NoCodesErrorType.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

/// NoCodesErrorType from No-Codes module
public enum NoCodesErrorType: Sendable {
  case unknown
  case `internal`
  case sdkInitializationError
  case productNotFound
  case productsLoadingFailed
  case invalidRequest
  case invalidResponse
  case authorizationFailed
  case critical
  case rateLimitExceeded
  case screenNotFound
  case screenLoadingFailed
  /// The screen loaded, but the SDK found nowhere in your UIKit hierarchy to
  /// put it: no view controller to present on, no navigation controller for a
  /// `push` presentation style, or the host is already presenting something
  /// else.
  ///
  /// Delivered to `NoCodesDelegate.noCodesFailedToLoadScreen(error:)` on the
  /// main actor. Nothing is shown, and `noCodesFinished()` follows as well
  /// unless a previously shown screen is still visible. Retry from a view
  /// controller that is on screen and not already presenting, or supply one
  /// from `NoCodesDelegate.controllerForNavigation()`.
  case screenPresentationFailed
  case clientError
  
  public func message() -> String {
    switch self {
    case .internal:
      return "Internal error occurred."
    case .sdkInitializationError:
      return "SDK is not initialized. Initialize SDK before calling other functions"
    case .screenLoadingFailed:
      return "Failed to load screen."
    case .screenPresentationFailed:
      return "Failed to present screen: no view controller available to present it on."
    case .productNotFound:
      return "The product not found."
    case .productsLoadingFailed:
      return "Failed to load products."
    case .screenNotFound:
      return "No-Code screen not found."
    case .clientError:
      return "An error occurred in the client code"
    default:
      return "Unknown error occurred."
    }
  }
}
