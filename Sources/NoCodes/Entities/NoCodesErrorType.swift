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
  /// The screen loaded, but no suitable view controller was available to
  /// present it on. Reported via `noCodesFailedToLoadScreen(error:)`, followed
  /// by `noCodesFinished()` unless another screen is still visible.
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
