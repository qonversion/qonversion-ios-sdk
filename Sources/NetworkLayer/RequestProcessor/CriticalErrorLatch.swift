//
//  CriticalErrorLatch.swift
//  Qonversion
//

import Foundation

/// The revoked-project-key stop switch, shared by every ``RequestProcessor``
/// of the Qonversion target.
///
/// Scope: the Qonversion target only — the NoCodes module ships its own
/// processor and is deliberately not wired to this latch.
///
/// There is no reset path: a revoked key stays revoked for the process.
// @unchecked: the latched error is lock-guarded.
final class CriticalErrorLatch: @unchecked Sendable {

    private let lock = NSLock()
    private var latched: QonversionError?

    var error: QonversionError? {
        lock.lock()
        defer { lock.unlock() }
        return latched
    }

    /// First error wins: later ones do not overwrite the one that stopped the SDK.
    func latch(_ error: QonversionError) {
        lock.lock()
        defer { lock.unlock() }
        guard latched == nil else { return }
        latched = error
    }
}
