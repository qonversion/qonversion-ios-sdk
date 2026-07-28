//
//  CriticalErrorLatch.swift
//  Qonversion
//

import Foundation

/// The revoked-project-key stop switch, shared by every ``RequestProcessor``
/// in the process.
///
/// A 401 / 402 / 403 does not describe the one request that got it — it means
/// the project key itself is dead, so every further call would get the same
/// answer. The SDK builds one processor per service on purpose, which is why
/// the latch cannot live inside a processor: the first service to see the
/// error must stop all of them at once. The ObjC SDK got this for free — it
/// had a single QNAPIClient.
///
/// There is no reset path: a revoked key stays revoked for the process.
///
/// One instance SDK-wide — see MiscAssembly.criticalErrorLatch().
// @unchecked: the latched error is lock-guarded.
final class CriticalErrorLatch: @unchecked Sendable {

    private let lock = NSLock()
    private var latched: QonversionError?

    var error: QonversionError? {
        lock.lock()
        defer { lock.unlock() }
        return latched
    }

    /// Latches the first critical error. Later ones do not overwrite it: the
    /// one that actually stopped the SDK is the one worth reporting.
    func latch(_ error: QonversionError) {
        lock.lock()
        defer { lock.unlock() }
        guard latched == nil else { return }
        latched = error
    }
}
