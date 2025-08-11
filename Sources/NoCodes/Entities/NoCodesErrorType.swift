//
//  NoCodesErrorType.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

/// NoCodesErrorType from No-Codes module
public enum NoCodesErrorType {
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
  case screenLoadingFailed
  
  public func message() -> String {
    switch self {
    case .internal:
      return "Internal error occurred."
    case .sdkInitializationError:
      return "SDK is not initialized. Initialize SDK before calling other functions"
    case .screenLoadingFailed:
      return "Failed to load screen."
    case .productsLoadingFailed:
      return "Failed to load products."
    default:
      return "Unknown error occurred."
    }
  }
}

#endif 