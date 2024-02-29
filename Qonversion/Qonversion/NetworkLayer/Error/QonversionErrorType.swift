//
//  QonversionErrorType.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

enum QonversionErrorType {
    case unknown
    case `internal`
    case invalidRequest
    case invalidResponse
    case authorizationFailed
    case critical
    case rateLimitExceeded
    case storeKitUnavailable
    
    func message() -> String {
        // handle other errors here
        switch self {
        case .internal:
            return "Internal error occurred"
        default:
            return "Unknown error occurred"
        }
    }
}
