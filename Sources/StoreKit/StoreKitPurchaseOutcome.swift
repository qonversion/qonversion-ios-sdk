//
//  StoreKitPurchaseOutcome.swift
//  Qonversion
//

import Foundation
import StoreKit

/// A store-agnostic result of a purchase attempt, mapped into integrator-facing
/// errors here so the mapping stays testable without real StoreKit objects.
enum StoreKitPurchaseOutcome {

    case success(Qonversion.Transaction)

    /// The user backed out of the payment sheet.
    case userCancelled

    /// The purchase awaits an external action (Ask to Buy / SCA).
    case pending

    /// StoreKit could not verify the transaction signature.
    case unverified(Error?)

    /// The store reported a failure.
    case failed(Error?)

    /// The integrator-facing error for this outcome; nil for success.
    func qonversionError() -> QonversionError? {
        switch self {
        case .success:
            return nil
        case .userCancelled:
            return QonversionError(type: .purchaseCancelled)
        case .pending:
            return QonversionError(type: .purchasePending)
        case .unverified(let error):
            return QonversionError(type: .transactionVerificationFailed, error: error)
        case .failed(let error):
            return QonversionError(type: Self.failureType(for: error), error: error)
        }
    }

    /// The integrator-facing error for a store failure raised outside the
    /// payment sheet; nothing raw may reach a public entry point.
    /// `fallbackType` names the operation for what the store cannot classify.
    ///
    /// A STORE-reported cancellation stays `.purchaseCancelled`; only the SDK
    /// abandoning the run becomes `.cancelled` — nothing failed, so the host
    /// must not retry.
    static func storeError(_ error: Error, fallbackType: QonversionErrorType) -> QonversionError {
        // Re-wrapping would nest messages and bury the precise type.
        if let qonversionError = error as? QonversionError { return qonversionError }

        // .purchaseFailed is failureType's "cannot name it" answer; everything
        // it CAN name, cancellations included, leaves through this guard.
        let storeType: QonversionErrorType = failureType(for: error)
        guard storeType == .purchaseFailed else { return QonversionError(type: storeType, error: error) }

        guard !error.isCancellation else { return QonversionError(type: .cancelled, error: error) }

        return QonversionError(type: fallbackType, error: error)
    }

    /// Maps the store's own failure kinds onto the SDK's error surface.
    static func failureType(for error: Error?) -> QonversionErrorType {
        guard let error else { return .purchaseFailed }

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .userCancelled:
                return .purchaseCancelled
            case .notAvailableInStorefront:
                return .storeProductNotAvailable
            case .notEntitled:
                return .paymentNotAllowed
            default:
                return .purchaseFailed
            }
        }

        if let purchaseError = error as? StoreKit.Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return .storeProductNotAvailable
            case .purchaseNotAllowed:
                return .paymentNotAllowed
            default:
                return .purchaseFailed
            }
        }

        return .purchaseFailed
    }
}
