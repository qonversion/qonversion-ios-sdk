//
//  StoreKitPurchaseOutcome.swift
//  Qonversion
//

import Foundation

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
            return QonversionError(type: .purchaseFailed, error: error)
        }
    }
}
