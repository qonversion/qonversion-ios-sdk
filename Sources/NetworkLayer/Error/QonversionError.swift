//
//  QonversionError.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

/// The error type of every failure the SDK throws. Switch on ``type`` to
/// react precisely — e.g. a cancelled purchase, a pending Ask to Buy
/// purchase and a network failure deserve different paywall UX.
// @unchecked: additionalInfo carries plist-like values only.
public struct QonversionError: Error, @unchecked Sendable {

    /// What exactly failed.
    public let type: QonversionErrorType

    /// A human-readable description, including the underlying error's one.
    public let message: String

    /// The underlying error, when the failure wraps one (e.g. a URLError).
    public let error: Error?

    /// Additional failure context.
    public let additionalInfo: [String: Any]?

    /// The backend error code (a snake_case slug, e.g. "relation_not_found"
    /// or "purchase_fraud") when the failure came from the API — branch on it
    /// for handling more specific than ``type``.
    public let apiCode: String?

    /// The backend error class when the failure came from the API:
    /// "internal", "logical", "request" or "resource". Absent on the
    /// `/v4/web` surface, which sends the envelope without it.
    public let apiType: String?

    init(type: QonversionErrorType, message: String? = nil, error: Error? = nil, additionalInfo: [String : Any]? = nil, apiCode: String? = nil, apiType: String? = nil) {
        var errorMessage: String = message ?? type.message()
        if let qonversionError = error as? QonversionError {
            errorMessage += "\n" + qonversionError.message
        } else if let error = error {
            errorMessage += "\n" + error.localizedDescription
        }

        self.type = type
        self.message = errorMessage
        self.error = error
        self.additionalInfo = additionalInfo
        self.apiCode = apiCode
        self.apiType = apiType
    }
    
    static func initializationError() -> QonversionError {
        return QonversionError(type: .sdkInitializationError)
    }
}

extension QonversionError: LocalizedError {

    public var errorDescription: String? { message }
}
