//
//  CrashReportsStorage.swift
//  Qonversion
//

import Foundation

/// Holds SDK crash reports between the launch that produced them and the one
/// that sends them.
///
/// Hard-bounded, unlike the ObjC implementation, which wrote one file per
/// exception into the app's Documents directory and never removed any of them
/// unless a send succeeded — an SDK crash loop against an unreachable endpoint
/// filled the user's storage with files their app also had to list.
// @unchecked: the read-modify-write is lock-guarded.
final class CrashReportsStorage: @unchecked Sendable {

    /// The oldest report is dropped first. Five is a diagnostic sample, not a
    /// log: the same bug produces the same stack, and the SDK is not a crash
    /// reporter.
    static var maxStoredReports: Int { 5 }

    private enum Constants: String {
        case reportsKey = "qonversion.keys.crashReports"
    }

    private let localStorage: LocalStorageInterface
    private let lock = NSLock()

    init(localStorage: LocalStorageInterface) {
        self.localStorage = localStorage
    }

    /// Called from the uncaught-exception handler, so it stays synchronous and
    /// does the least it can: the process is about to die.
    func store(_ report: CrashReport) {
        lock.lock()
        defer { lock.unlock() }

        var reports: [CrashReport] = storedReports()
        reports.append(report)
        if reports.count > Self.maxStoredReports {
            reports.removeFirst(reports.count - Self.maxStoredReports)
        }

        try? localStorage.set(reports, forKey: Constants.reportsKey.rawValue)
    }

    func all() -> [CrashReport] {
        lock.lock()
        defer { lock.unlock() }

        return storedReports()
    }

    func remove(_ report: CrashReport) {
        lock.lock()
        defer { lock.unlock() }

        var reports: [CrashReport] = storedReports()
        reports.removeAll { $0.id == report.id }
        try? localStorage.set(reports, forKey: Constants.reportsKey.rawValue)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        localStorage.removeObject(forKey: Constants.reportsKey.rawValue)
    }

    private func storedReports() -> [CrashReport] {
        return (try? localStorage.object(forKey: Constants.reportsKey.rawValue, dataType: [CrashReport].self)) ?? []
    }
}
