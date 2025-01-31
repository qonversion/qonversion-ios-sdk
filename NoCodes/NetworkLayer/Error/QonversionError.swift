//
//  QonversionError.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

struct QonversionError: Error {
    public let type: QonversionErrorType
    public let message: String
    public let error: Error?
    public let additionalInfo: [String: Any]?

    init(type: QonversionErrorType, message: String? = nil, error: Error? = nil, additionalInfo: [String : Any]? = nil) {
        var errorMessage = message ?? type.message()
        if let qonversionError = error as? QonversionError {
            errorMessage += "\n" + qonversionError.message
        } else if let error = error {
            errorMessage += "\n" + error.localizedDescription
        }

        self.type = type
        self.message = errorMessage
        self.error = error
        self.additionalInfo = additionalInfo
    }
    
    static func initializationError() -> QonversionError {
        return QonversionError(type: .sdkInitializationError)
    }
}
