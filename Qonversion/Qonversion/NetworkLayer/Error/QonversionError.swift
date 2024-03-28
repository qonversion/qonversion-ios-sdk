//
//  QonversionError.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

struct QonversionError: Error {
    let type: QonversionErrorType
    let message: String?
    let error: Error?
    let additionalInfo: [String: Any]?
    
    init(type: QonversionErrorType, message: String? = nil, error: Error? = nil, additionalInfo: [String : Any]? = nil) {
        self.type = type
        self.message = message ?? type.message()
        self.error = error
        self.additionalInfo = additionalInfo
    }
    
    static func initializationError() -> QonversionError {
        return QonversionError(type: .sdkInitializationError)
    }
}
