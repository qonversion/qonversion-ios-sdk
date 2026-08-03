//
//  QonversionError.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

/// The error type of every failure the SDK throws. Switch on ``type`` to
/// react precisely — e.g. a cancelled purchase, a pending Ask to Buy
/// purchase and a network failure deserve different paywall UX.
// @unchecked: additionalInfo carries plist-like values only.
public struct QonversionError: Error, @unchecked Sendable {

    /// What exactly failed.
    public let type: QonversionErrorType

    /// A human-readable description, including the underlying error's one.
    public let message: String

    /// The underlying error, when the failure wraps one (e.g. a URLError).
    public let error: Error?

    /// Additional failure context.
    public let additionalInfo: [String: Any]?

    /// The backend error code (a snake_case slug, e.g. "relation_not_found"
    /// or "purchase_fraud") when the failure came from the API — branch on it
    /// for handling more specific than ``type``.
    public let apiCode: String?

    /// The backend error class when the failure came from the API:
    /// "internal", "logical", "request" or "resource". Absent on the
    /// `/v4/web` surface, which sends the envelope without it.
    public let apiType: String?

    init(type: QonversionErrorType, message: String? = nil, error: Error? = nil, additionalInfo: [String : Any]? = nil, apiCode: String? = nil, apiType: String? = nil) {
        var errorMessage: String = message ?? type.message()
        let wrappedError: QonversionError? = error as? QonversionError
        if let wrappedError {
            errorMessage += "\n" + wrappedError.message
        } else if let error = error {
            errorMessage += "\n" + error.localizedDescription
        }

        self.type = type
        self.message = errorMessage
        self.error = error
        self.additionalInfo = additionalInfo
        // A service names the operation that failed, but only the backend can
        // classify WHY — that classification must survive the wrapping.
        self.apiCode = apiCode ?? wrappedError?.apiCode
        self.apiType = apiType ?? wrappedError?.apiType
    }
    
    static func initializationError() -> QonversionError {
        return QonversionError(type: .sdkInitializationError)
    }
}

extension QonversionError: LocalizedError {

    public var errorDescription: String? { message }
}

extension Error {

    /// Cancellation reaches the SDK in more than one shape: a task cancelled
    /// while suspended in URLSession surfaces as `URLError(.cancelled)`,
    /// wrapped in the SDK error of whichever layer failed, while the SDK's own
    /// generation guards throw `CancellationError` directly.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let qonversionError = self as? QonversionError {
            if qonversionError.type == .cancelled { return true }
            if let underlying: Error = qonversionError.error {
                return underlying.isCancellation
            }
        }

        return false
    }

    /// The status the backend answered with, wherever it sits in the chain of
    /// errors the layers above wrapped it in.
    var backendStatusCode: Int? {
        guard let qonversionError = self as? QonversionError else { return nil }
        if let statusCode = qonversionError.additionalInfo?[ErrorConstants.statusCodeKey.rawValue] as? Int {
            return statusCode
        }

        return qonversionError.error?.backendStatusCode
    }

    /// The backend refused the request rather than failing to answer it: any
    /// 4xx but the ones that clear on their own. Repeating such a request gets
    /// the same answer forever, so the caller has to stop instead of retrying.
    ///
    /// 401/402/403 are excluded: they describe the state of the project (a
    /// revoked key, an overdue account, a misconfigured proxy), not a verdict
    /// on the request, and they clear once the project is fixed. The critical
    /// error latch and the replay queue handle those.
    ///
    /// 404 is excluded too: on a nested route it says the user (or the mapped
    /// product) is not there YET, not that the request was refused — the
    /// backend answers `not_found`/`relation_not_found` for that, and the SDK
    /// itself reads a 404 as an absent entity (``UserService/identity(for:)``).
    /// The report stays retriable: the transaction is neither finished nor
    /// blacklisted.
    var isRejectedByBackend: Bool {
        guard let statusCode: Int = backendStatusCode else { return false }

        return (ResponseCode.clientErrorMin.rawValue...ResponseCode.clientErrorMax.rawValue).contains(statusCode)
            && statusCode != ResponseCode.tooManyRequests.rawValue
            && statusCode != ResponseCode.requestTimeout.rawValue
            && statusCode != ResponseCode.unauthorized.rawValue
            && statusCode != ResponseCode.paymentRequired.rawValue
            && statusCode != ResponseCode.forbidden.rawValue
            && statusCode != ResponseCode.notFound.rawValue
    }

    /// The backend refused the PURCHASE, not the request that carried it: a
    /// fraud verdict or a payload its validation could never accept. No client
    /// version reports such a transaction successfully, so the SDK may finish
    /// it — which destroys the store's only copy.
    ///
    /// A bare 400 (`invalid_data`, `invalid_request`) and every unmapped 4xx
    /// stay out: they say the SDK built the body wrong, and a fixed client
    /// reports the very same purchase successfully.
    var isUnacceptablePurchase: Bool {
        guard isRejectedByBackend, let qonversionError = self as? QonversionError else { return false }
        // The verdict travels in the API code, which survives the wrapping the
        // layers above add; their own `type` describes the operation instead.
        guard let verdict: QonversionErrorType = QonversionErrorType(apiCode: qonversionError.apiCode) else { return false }

        return verdict == .fraudPurchase || verdict == .receiptValidationError
    }

    /// What a public API is allowed to throw. Every public entry point
    /// documents ``QonversionError``, so a bare `CancellationError` — a Swift
    /// runtime type that no `catch let error as QonversionError` can classify
    /// — must never reach the host. Anything already classified passes
    /// through untouched.
    var classifiedForPublicAPI: Error {
        guard isCancellation else { return self }
        // Already named for what it is; re-wrapping would only nest messages.
        if let qonversionError = self as? QonversionError, qonversionError.type == .cancelled { return self }

        return QonversionError(type: .cancelled, message: nil, error: self)
    }
}
