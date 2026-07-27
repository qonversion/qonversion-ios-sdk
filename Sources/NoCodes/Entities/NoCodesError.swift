//
//  NoCodesError.swift
//  NoCodes
//
//  Created by Suren Sarkisyan on 20.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

/// NoCodesError type from No-Codes module
// @unchecked: every stored property is a `let`, and the only values the SDK
// ever puts into `additionalInfo` are immutable strings taken from the response.
public struct NoCodesError: Error, @unchecked Sendable {
  public let type: NoCodesErrorType
  public let message: String
  public let error: Error?
  public let additionalInfo: [String: Any]?

  init(type: NoCodesErrorType, message: String? = nil, error: Error? = nil, additionalInfo: [String : Any]? = nil) {
    var errorMessage = message ?? type.message()
    if let noCodesError = error as? NoCodesError {
      errorMessage += "\n" + noCodesError.message
    } else if let error = error {
      errorMessage += "\n" + error.localizedDescription
    }

    self.type = type
    self.message = errorMessage
    self.error = error
    self.additionalInfo = additionalInfo
  }
  
  static func initializationError() -> NoCodesError {
    return NoCodesError(type: .sdkInitializationError)
  }
  
  static func fromClientError(_ error: Error?) -> NoCodesError {
    return NoCodesError(type: .clientError, error: error)
  }
}
