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
    /// visionOS only: a purchase was attempted before the app named the
    /// `UIScene` its purchase sheet must be confirmed in. Call
    /// ``Qonversion/Qonversion/setPurchaseConfirmationScene(_:)`` first.
    case purchaseSceneMissing
    /// The backend does not know the requested resource: an unknown user id,
    /// an unknown product, an unknown remote config, an unknown nested id.
    /// Answers the `not_found` and `relation_not_found` backend codes
    /// (HTTP 404).
    case resourceNotFound
    /// This device is not allowed to make payments (e.g. parental controls).
    /// Produced from StoreKit failures only — the backend has no code for it.
    case paymentNotAllowed
    /// The product is not available in the current storefront. Produced from
    /// StoreKit failures only — the backend has no code for it.
    case storeProductNotAvailable
    /// The backend rejected the purchase as fraudulent (`purchase_fraud`).
    case fraudPurchase
    /// The backend could not turn the purchase into a subscription record:
    /// the App Store payload did not parse or contradicts a known purchase.
    case receiptValidationError
    /// The project is misconfigured in the Qonversion Dashboard — usually a
    /// missing or invalid App Store credential.
    case projectConfigError
    /// The current user (or the requested context key) has no remote
    /// configuration. The ObjC SDK's QONErrorCodeRemoteConfigurationNotAvailable:
    /// it is a normal state of an unconfigured project or a user outside every
    /// experiment, not a transport or schema failure.
    ///
    /// A user the backend does not know arrives the same way and is not
    /// distinguishable from it: both are answered with the same code, and there
    /// will be no separate one. Either way there is nothing to apply, so the
    /// app falls back to its own defaults.
    case remoteConfigurationNotAvailable
    /// The operation was abandoned before it could answer, because the SDK
    /// switched users (a logout or an identify resolving to another user)
    /// while it was in flight — its answer would have described a user that is
    /// no longer current. Ask again; the call is safe to repeat.
    case cancelled
    /// No response arrived: the device is offline, the connection dropped, the
    /// host could not be resolved or the request timed out. Distinct from
    /// ``invalidResponse``, where the backend did answer.
    ///
    /// The request most likely never reached the backend, so retrying once
    /// connectivity is back is the right move. A timeout is the one case where
    /// it may have arrived and been processed anyway — repeating a read is
    /// always safe, repeating a write may duplicate it.
    case networkConnectionFailed

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
        case .purchaseSceneMissing:
            return "On visionOS the purchase sheet is confirmed in a scene. Call Qonversion.shared.setPurchaseConfirmationScene(_:) with the UIScene the purchase is made from before purchasing."
        case .resourceNotFound:
            return "The requested resource was not found"
        case .invalidRequest:
            return "The request was rejected as invalid"
        case .rateLimitExceeded:
            return "The request rate limit was exceeded"
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
        case .remoteConfigurationNotAvailable:
            return "Remote configuration is not available for the current user or for the provided context key"
        case .cancelled:
            return "The request was cancelled because the SDK switched users"
        case .networkConnectionFailed:
            return "The request could not reach Qonversion: the network connection failed"
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

    /// The backend error codes that carry a meaning of their own; anything
    /// absent keeps the classification derived from the HTTP status.
    ///
    /// v4 answers `{"error": {"type", "code", "message", "details"}}` where
    /// `code` is a snake_case slug. The vocabulary below is the one that
    /// actually reaches a mobile client — every entry was read off the
    /// api-gateway, userman, purchaseman and receipter sources. A slug that is
    /// not listed keeps the status-derived type on purpose: guessing a meaning
    /// for it would send the integrator down the wrong branch.
    init?(apiCode: String?) {
        guard let apiCode else { return nil }

        if let slugType = QonversionErrorType(apiCodeSlug: apiCode) {
            self = slugType
            return
        }

        // The numeric codes belong to the v0/v1 API generation and are kept
        // only for a proxy or an old deployment still answering with them.
        // 10008 is the single numeric code a live backend can still emit;
        // the rest of the old table mapped codes nothing produces anymore.
        guard let code = Int(apiCode) else { return nil }

        switch code {
        case 10008:
            self = .fraudPurchase
        default:
            return nil
        }
    }

    private init?(apiCodeSlug: String) {
        switch apiCodeSlug {
        // The request was malformed or failed validation. `invalid_data` and
        // `invalid_request` come from the gateway, `validation_error` from the
        // offer-signature service and `invalid_entitlement_data` from userman.
        case "invalid_data", "invalid_request", "validation_error", "invalid_entitlement_data":
            self = .invalidRequest
        // Nothing behind the id. `relation_not_found` is what a nested route
        // answers for an unknown uid (404).
        case "not_found", "relation_not_found":
            self = .resourceNotFound
        // Throttling: the gateway's slug (429).
        case "too_many_requests":
            self = .rateLimitExceeded
        // purchaseman rejected the purchase as fraudulent (422).
        case "purchase_fraud":
            self = .fraudPurchase
        // The project has no usable App Store credentials. The first two come
        // from purchaseman, `token_not_found` and `secrets_not_found` from the
        // offer-signature service (the latter on a project without App Store
        // Connect credentials): the Dashboard project is not set up for this
        // operation.
        case "store_not_configured", "store_creds_failed", "token_not_found", "secrets_not_found":
            self = .projectConfigError
        // The purchase-validation family (422): the App Store payload did not
        // parse into a subscription, carried an unexpected purchase type, or
        // contradicts a purchase the backend already knows.
        case "subscription_period_parse_error", "apple_purchase_type_error", "conflicting_purchase_found":
            self = .receiptValidationError
        default:
            // Deliberately unmapped, though they do reach the client:
            // already_exists, storage_error, network_error, unknown_error,
            // unexpected_error, entity_persistence_error,
            // client_canceled_request — they add nothing to the HTTP status.
            // control_unauthorized / control_forbidden are unmapped too: they
            // arrive on 401 / 403, which already classify as .critical and
            // must keep doing so (see the precedence in NetworkErrorHandler).
            // user_not_found, rate_limit_exceeded and settings_not_found are
            // absent on purpose: no backend emits them.
            return nil
        }
    }
}
