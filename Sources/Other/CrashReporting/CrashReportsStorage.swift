//
//  CrashReportsStorage.swift
//  Qonversion
//

import Foundation

/// Holds SDK crash reports between the launch that produced them and the one
/// that sends them. Hard-bounded, so a crash loop against an unreachable
/// endpoint cannot grow without limit.
// @unchecked: the read-modify-write is lock-guarded.
final class CrashReportsStorage: @unchecked Sendable {

    /// Oldest dropped first. A diagnostic sample, not a log.
    static var maxStoredReports: Int { 5 }

    private enum Constants: String {
        case reportsKey = "qonversion.keys.crashReports"
    }

    private let localStorage: LocalStorageInterface
    private let lock = NSLock()

    init(localStorage: LocalStorageInterface) {
        self.localStorage = localStorage
    }

    /// Called from the uncaught-exception handler, so it stays synchronous.
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

    /// Persists the attempt counter in place. A report that is no longer
    /// stored is not resurrected.
    func replace(_ report: CrashReport, with replacement: CrashReport) {
        lock.lock()
        defer { lock.unlock() }

        var reports: [CrashReport] = storedReports()
        guard let index: Int = reports.firstIndex(where: { $0.id == report.id }) else { return }

        reports[index] = replacement
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
