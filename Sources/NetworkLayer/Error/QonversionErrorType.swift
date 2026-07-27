//
//  QonversionErrorType.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

/// Every failure kind the SDK can throw, exposed on ``QonversionError/type``.
public enum QonversionErrorType: Sendable {
    case unknown
    case `internal`
    case sdkInitializationError
    case invalidRequest
    case invalidResponse
    case authorizationFailed
    case critical
    case rateLimitExceeded
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
    case purchaseInProgress
    case purchasePending
    case purchaseFailed
    case transactionVerificationFailed
    /// The product is not in the Qonversion catalog.
    case productNotFound
    /// This device is not allowed to make payments (e.g. parental controls).
    case paymentNotAllowed
    /// The product is not available in the current storefront.
    case storeProductNotAvailable
    /// The backend rejected the purchase as fraudulent.
    case fraudPurchase
    /// The backend could not validate the purchase with Apple.
    case receiptValidationError
    /// The project is misconfigured in the Qonversion Dashboard.
    case projectConfigError
    /// The feature is not available on the project's plan.
    case featureNotSupported
    /// The backend does not know this user id.
    case invalidClientUID

    public func message() -> String {
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
        case .purchaseInProgress:
            return "A purchase of this product is already in progress"
        case .purchasePending:
            return "The purchase is pending an external action (Ask to Buy / SCA)"
        case .purchaseFailed:
            return "The purchase failed"
        case .transactionVerificationFailed:
            return "The transaction failed StoreKit verification"
        case .productNotFound:
            return "The product was not found in the Qonversion product catalog"
        case .paymentNotAllowed:
            return "This device is not allowed to make payments"
        case .storeProductNotAvailable:
            return "The product is not available in the current storefront"
        case .fraudPurchase:
            return "The purchase was rejected as fraudulent"
        case .receiptValidationError:
            return "Failed to validate the purchase with the App Store"
        case .projectConfigError:
            return "The Qonversion project is misconfigured. Check the project settings in the Dashboard."
        case .featureNotSupported:
            return "The feature is not supported for the current project"
        case .invalidClientUID:
            return "The Qonversion user id is unknown to the backend"
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

extension QonversionErrorType {

    /// The backend error codes that carry a meaning of their own. Taken from
    /// the production error mapper; anything absent keeps the classification
    /// derived from the HTTP status.
    init?(apiCode: String?) {
        guard let apiCode, let code = Int(apiCode) else { return nil }

        switch code {
        case 10004, 10005, 20014:
            self = .invalidClientUID
        case 10008:
            self = .fraudPurchase
        case 20005:
            self = .featureNotSupported
        case 20011, 20012, 20013:
            self = .projectConfigError
        case 20100, 20102, 20103, 20105, 20107, 20108, 20110, 21099:
            self = .receiptValidationError
        default:
            return nil
        }
    }
}
