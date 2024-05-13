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
    case productsLoadingFailed
    case entitlementsLoadingFailed
    case offeringsLoadingFailed
    case storeProductsLoadingFailed
    case loadingRemoteConfigFailed
    case loadingRemoteConfigListFailed
    case attachingUserToRemoteConfigFailed
    case detachingUserFromRemoteConfigFailed
    case attachingUserToExperimentFailed
    case detachingUserFromExperimentFailed
    case storageSerializationFailed
    case storageDeserializationFailed

    func message() -> String {
        // handle other errors here
        switch self {
        case .internal:
            return "Internal error occurred."
        case .sdkInitializationError:
            return "SDK is not initialized. Initialize SDK before calling other functions using  Qonversion.initialize()."
        case .unableToSerializeDevice:
            return "Device serialization failed. Unable to send request."
        case .deviceCreationFailed:
            return "Device creation request failed. Unable to create the device."
        case .deviceUpdateFailed:
            return "Device update request failed. Unable to update the device."
        case .productsLoadingFailed:
            return "Products loading request failed."
        case .entitlementsLoadingFailed:
            return "Entitlements loading request failed."
        case .offeringsLoadingFailed:
            return "Offerings loading request failed."
        case .storeProductsLoadingFailed:
            return "Store products loading failed."
        case .loadingRemoteConfigFailed:
            return "Failed to load remote config."
        case .loadingRemoteConfigListFailed:
            return "Failed to load remote config list."
        case .attachingUserToRemoteConfigFailed:
            return "Failed to attach user to the remote config."
        case .detachingUserFromRemoteConfigFailed:
            return "Failed to detach user from the remote config."
        case .attachingUserToExperimentFailed:
            return "Failed to attach user to the experiment."
        case .detachingUserFromExperimentFailed:
            return "Failed to detach user from the experiment."
        case .storageSerializationFailed:
            return "Failed to serialize data to save to the storage"
        case .storageDeserializationFailed:
            return "Failed to deserialize data from the storage"
        default:
            return "Unknown error occurred."
        }
    }
}
