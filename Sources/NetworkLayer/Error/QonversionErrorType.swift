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
    case productPermissionsLoadingFailed
    case entitlementsLoadingFailed
    case storeProductsLoadingFailed
    case loadingRemoteConfigFailed
    case loadingRemoteConfigListFailed
    case attachingUserToRemoteConfigFailed
    case detachingUserFromRemoteConfigFailed
    case attachingUserToExperimentFailed
    case detachingUserFromExperimentFailed
    case storageSerializationFailed
    case storageDeserializationFailed
    case identityLoadingFailed
    case identityCreationFailed
    case purchaseReportingFailed
    case promoOfferSigningFailed
    case promoPurchaseIntentAlreadyHandled
    case restoreFailed
    case purchaseCancelled
    case purchasePending
    case purchaseFailed
    case transactionVerificationFailed

    func message() -> String {
        // handle other errors here
        switch self {
        case .internal:
            return "Internal error occurred."
        case .sdkInitializationError:
            return "SDK is not initialized. Initialize SDK before calling other functions using  Qonversion.initialize()."
        case .unableToSerializeDevice:
            return "Device serialization failed. Unable to send request."
        case .storageSerializationFailed:
            return "Failed to serialize data to save to the storage"
        case .storageDeserializationFailed:
            return "Failed to deserialize data from the storage"
        case .identityLoadingFailed:
            return "Failed to load user identity"
        case .identityCreationFailed:
            return "Failed to link user identity"
        case .purchaseReportingFailed:
            return "The purchase succeeded in the store but could not be reported to Qonversion; it will be retried"
        case .restoreFailed:
            return "Failed to restore purchases"
        case .purchaseCancelled:
            return "The user canceled the purchase"
        case .purchasePending:
            return "The purchase is pending an external action (Ask to Buy / SCA)"
        case .purchaseFailed:
            return "The purchase failed"
        case .transactionVerificationFailed:
            return "The transaction failed StoreKit verification"
        case .deviceCreationFailed:
            return "Device creation request failed. Unable to create the device."
        case .deviceUpdateFailed:
            return "Device update request failed. Unable to update the device."
        case .productPermissionsLoadingFailed:
            return "Failed to load the product permissions mapping"
        case .entitlementsLoadingFailed:
            return "Failed to load user entitlements"
        case .productsLoadingFailed:
            return "Products loading request failed."
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
        default:
            return "Unknown error occurred."
        }
    }
}
