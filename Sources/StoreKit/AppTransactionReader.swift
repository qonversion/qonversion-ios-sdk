//
//  AppTransactionReader.swift
//  Qonversion
//

import Foundation
import StoreKit

/// Reads the original app version from the StoreKit app transaction.
///
/// The value never changes for an install, and the underlying read may hit the
/// network, so an ANSWER is resolved once per process: the first caller starts
/// the read, concurrent callers join it, and everyone afterwards gets the
/// settled answer without touching StoreKit again. A read that throws is a
/// transient store failure, not an answer — it stays retryable, so one offline
/// launch does not cost the install its original app version for the whole
/// process. No failure ever reaches the caller: the field is informational and
/// must never cost the host a stalled user request.
///
/// The store read is injectable so the resolution rules can be tested without
/// a StoreKit session, mirroring `AdvertisingIdReader.RawIdentifierReader`.
actor AppTransactionReader: AppTransactionReaderInterface {

    typealias OriginalAppVersionReader = @Sendable () async throws -> String?

    /// A read either answers — with a version or with a legitimate nil on old
    /// systems — or fails, and only an answer settles.
    private enum ReadOutcome: Sendable {
        case answered(String?)
        case failed

        var version: String? {
            guard case .answered(let version) = self else { return nil }

            return version
        }
    }

    private let readOriginalAppVersion: OriginalAppVersionReader

    /// Double optional: the outer level marks "already resolved", the inner one
    /// carries the answer, which is legitimately nil on old systems.
    private var resolved: String??
    private var inFlight: Task<ReadOutcome, Never>?

    init(originalAppVersionReader: @escaping OriginalAppVersionReader = AppTransactionReader.storeOriginalAppVersion) {
        self.readOriginalAppVersion = originalAppVersionReader
    }

    func originalAppVersion() async -> String? {
        if let resolved { return resolved }
        if let inFlight { return await inFlight.value.version }

        let read: OriginalAppVersionReader = readOriginalAppVersion
        let task = Task<ReadOutcome, Never> {
            do {
                return .answered(try await read())
            } catch {
                return .failed
            }
        }
        inFlight = task

        let outcome: ReadOutcome = await task.value
        if case .answered(let version) = outcome {
            resolved = .some(version)
        }
        inFlight = nil

        return outcome.version
    }

    /// The StoreKit 2 app transaction is unavailable below iOS 16, macOS 13,
    /// tvOS 16 and watchOS 9 — there the version is simply unknown.
    @Sendable
    static func storeOriginalAppVersion() async throws -> String? {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) else { return nil }

        let result: VerificationResult<AppTransaction> = try await AppTransaction.shared
        guard case .verified(let appTransaction) = result else { return nil }

        return appTransaction.originalAppVersion
    }
}
