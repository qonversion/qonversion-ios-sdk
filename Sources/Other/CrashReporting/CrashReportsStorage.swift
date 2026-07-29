//
//  CrashReportsStorage.swift
//  Qonversion
//

import Foundation

/// Holds SDK crash reports between the launch that produced them and the one
/// that sends them. Hard-bounded, so a crash loop against an unreachable
/// endpoint cannot grow without limit.
///
/// Every report is kept in two places: `UserDefaults`, which is where the SDK
/// keeps everything else, and a file — see ``CrashReportsFileStore`` for why
/// the defaults copy alone cannot be trusted to exist after the process is
/// aborted. Reads merge both, so a report the defaults never received is still
/// sent, and every write reconciles the two.
// @unchecked: the read-modify-write is lock-guarded.
final class CrashReportsStorage: @unchecked Sendable {

    /// Oldest dropped first. A diagnostic sample, not a log.
    static var maxStoredReports: Int { 5 }

    private enum Constants: String {
        case reportsKey = "qonversion.keys.crashReports"
    }

    private let localStorage: LocalStorageInterface
    private let fileStore: CrashReportsFileStore
    private let lock = NSLock()

    init(localStorage: LocalStorageInterface, fileStore: CrashReportsFileStore) {
        self.localStorage = localStorage
        self.fileStore = fileStore
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

        persist(reports)
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
        persist(reports)
    }

    /// Persists the attempt counter in place. A report that is no longer
    /// stored is not resurrected.
    func replace(_ report: CrashReport, with replacement: CrashReport) {
        lock.lock()
        defer { lock.unlock() }

        var reports: [CrashReport] = storedReports()
        guard let index: Int = reports.firstIndex(where: { $0.id == report.id }) else { return }

        reports[index] = replacement
        persist(reports)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        localStorage.removeObject(forKey: Constants.reportsKey.rawValue)
        fileStore.clear()
    }

    /// The union of both sources, defaults first and file entries the defaults
    /// never got appended after — so a lost flush costs ordering at worst,
    /// never the report.
    private func storedReports() -> [CrashReport] {
        let stored: [CrashReport] = (try? localStorage.object(forKey: Constants.reportsKey.rawValue, dataType: [CrashReport].self)) ?? []
        var known: Set<String> = Set(stored.map { $0.id })
        var merged: [CrashReport] = stored

        for report in fileStore.read() where known.insert(report.id).inserted {
            merged.append(report)
        }
        if merged.count > Self.maxStoredReports {
            merged.removeFirst(merged.count - Self.maxStoredReports)
        }

        return merged
    }

    private func persist(_ reports: [CrashReport]) {
        try? localStorage.set(reports, forKey: Constants.reportsKey.rawValue)
        fileStore.write(reports)
    }
}
