//
//  QonversionErrorType.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

enum QonversionErrorType {
    case unknown
    case `internal`
    case sdkInitializationError
    case invalidRequest
    case invalidResponse
    case authorizationFailed
    case critical
    case rateLimitExceeded
    case storeKitUnavailable
    case userLoadingFailed
    case userCreationFailed
    case deviceCreationFailed
    case deviceUpdateFailed
    case unableToSerializeDevice
    
    func message() -> String {
        // handle other errors here
        switch self {
        case .internal:
            return "Internal error occurred"
        case .sdkInitializationError:
            return "SDK is not initialized. Initialize SDK before calling other functions using  Qonversion.initialize()"
        case .unableToSerializeDevice:
            return "Device serialization failed. Unable to send request."
        case .deviceCreationFailed:
            return "Device creation request failed. Unable to create the device."
        case .deviceUpdateFailed:
            return "Device update request failed. Unable to update the device."
        default:
            return "Unknown error occurred"
        }
    }
}
