//
//  CrashReportsFileStore.swift
//  Qonversion
//

import Foundation

/// The durable half of crash-report persistence: one atomically written file
/// under the SDK's own directory in the app container.
///
/// ``CrashReportsStorage`` writes to `UserDefaults` from inside the uncaught
/// exception handler, and that write is handed to `cfprefsd` over XPC and
/// flushed on its own schedule. The default handler calls `abort()` the moment
/// the handler chain returns, so the process is killed by SIGABRT before
/// `cfprefsd` has any obligation to have written anything — the report is
/// simply gone. Apple's own guidance is that `UserDefaults` is not a place to
/// put data that has to be there after an abnormal termination, and
/// `synchronize()` has been deprecated since iOS 12 precisely because it never
/// gave that guarantee either.
///
/// `Data.write(to:options:.atomic)` does: it writes a temporary file and
/// `rename(2)`s it into place, entirely inside this process and entirely
/// synchronously, so it has either fully happened or not happened at all by the
/// time the handler returns.
///
/// The directory is created once at initialization, never from the handler.
// @unchecked: the URL and the coders are immutable after init; writes are
// serialized by the caller's lock.
final class CrashReportsFileStore: @unchecked Sendable {

    private enum Constants: String {
        case directoryName = "Qonversion"
        case fileName = "crash-reports.json"
        case unknownBundleId = "unknown"
    }

    private let fileURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// A nil `directory` disables the file mirror entirely — the storage then
    /// behaves exactly as it did before, rather than losing the report.
    init(directory: URL?, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
        self.fileURL = Self.prepared(directory: directory)?.appendingPathComponent(Constants.fileName.rawValue)
    }

    /// Application Support rather than Caches: the system may evict Caches at
    /// any time, and evicting the only surviving copy of a crash report is the
    /// failure this type exists to prevent.
    ///
    /// The bundle identifier is part of the path because Application Support of
    /// a non-sandboxed macOS process is the user's own folder, shared by every
    /// app: without it one app would send another vendor's stack traces under
    /// its own project key, and never send its own.
    static func defaultDirectory() -> URL? {
        guard let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }

        return base
            .appendingPathComponent(Constants.directoryName.rawValue)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? Constants.unknownBundleId.rawValue)
    }

    func read() -> [CrashReport] {
        guard let fileURL, let data: Data = try? Data(contentsOf: fileURL) else { return [] }

        return (try? decoder.decode([CrashReport].self, from: data)) ?? []
    }

    /// Runs while the process is dying, so it does nothing but encode and one
    /// atomic write.
    func write(_ reports: [CrashReport]) {
        guard let fileURL else { return }
        guard !reports.isEmpty else { return clear() }
        guard let data: Data = try? encoder.encode(reports) else { return }

        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        guard let fileURL else { return }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func prepared(directory: URL?) -> URL? {
        guard var directory else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        // Diagnostics of a build the user may no longer be running have no
        // business travelling to a new device in a backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)

        return directory
    }
}
