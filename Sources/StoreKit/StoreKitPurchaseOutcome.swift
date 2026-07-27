//
//  StoreKitPurchaseOutcome.swift
//  Qonversion
//

import Foundation
import StoreKit

/// A store-agnostic result of a purchase attempt. Produced by the thin
/// StoreKit wrappers and mapped into granular integrator-facing errors here,
/// so the mapping stays unit-testable without real StoreKit objects.
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

    /// Maps the store's own failure kinds onto the SDK's error surface, so an
    /// integrator can branch on `type` instead of digging into the underlying
    /// StoreKit error.
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
