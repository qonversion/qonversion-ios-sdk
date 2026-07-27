//
//  CrashReporter.swift
//  Qonversion
//

import Foundation

/// Reports crashes that came out of the SDK itself, so a bug shipped to
/// customers is visible without waiting for somebody to notice and file it.
///
/// Scope, deliberately the same as the ObjC SDK's QONExceptionManager:
/// **NSException only**. No signal handlers, no Mach exception ports — a
/// general-purpose crash reporter is what the host app already has, and two of
/// them fighting over the same handlers is a bigger problem than the one this
/// solves. It also means real crashes (SIGSEGV, a Swift runtime trap) are NOT
/// captured; what is captured is the ObjC exception family, which is where an
/// SDK-side misuse of Foundation/StoreKit surfaces.
///
/// The previously installed handler is always called afterwards, so installing
/// this never costs the host its own crash reporter.
///
/// The endpoint (`POST v4/sdk-crashes`) DOES NOT EXIST YET. Everything here is
/// built to fail softly against that: a send that fails leaves the report
/// queued, the queue is hard-bounded at
/// ``CrashReportsStorage/maxStoredReports``, and no failure ever reaches the
/// host. The proposed body is documented on ``CrashReport``.
// @unchecked: the installed state is lock-guarded and the handler is a C
// function pointer, which cannot capture anything.
final class CrashReporter: @unchecked Sendable {

    /// The C exception handler cannot capture context, so the reporter it
    /// dispatches to has to be reachable statically.
    static let shared = CrashReporter()

    private let lock = NSLock()
    private var storage: CrashReportsStorage?
    private var appExecutableName: String = ""
    private var previousHandler: (@convention(c) (NSException) -> Void)?
    private var isInstalled = false

    /// Chains: the handler installed before this one runs after it, always.
    func install(storage: CrashReportsStorage, appExecutableName: String = CrashReportFilter.currentAppExecutableName()) {
        lock.lock()
        defer { lock.unlock() }

        self.storage = storage
        self.appExecutableName = appExecutableName
        guard !isInstalled else { return }

        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handle(exception)
        }
        isInstalled = true
    }

    /// Runs while the process is dying: no async work, no allocation beyond
    /// what the report needs, and the previous handler is called whatever
    /// happens here.
    func handle(_ exception: NSException) {
        lock.lock()
        let storage: CrashReportsStorage? = self.storage
        let appExecutableName: String = self.appExecutableName
        let previousHandler: (@convention(c) (NSException) -> Void)? = self.previousHandler
        lock.unlock()

        if let storage,
           let linkage: CrashReport.Linkage = CrashReportFilter.linkage(ofCallStackSymbols: exception.callStackSymbols, appExecutableName: appExecutableName) {
            let report = CrashReport(
                name: exception.name.rawValue,
                reason: exception.reason ?? CrashReport.unknownReason,
                stackTrace: exception.callStackSymbols,
                linkage: linkage
            )
            storage.store(report)
        }

        previousHandler?(exception)
    }

    /// Test seam: puts the handler back the way it was found.
    func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        guard isInstalled else { return }

        NSSetUncaughtExceptionHandler(previousHandler)
        previousHandler = nil
        storage = nil
        isInstalled = false
    }
}

/// Ships the reports the previous launch left behind.
struct CrashReportsSender {

    private let storage: CrashReportsStorage
    private let requestProcessor: RequestProcessorInterface
    private let userIdProvider: UserIdProvider
    private let platform: String

    init(storage: CrashReportsStorage, requestProcessor: RequestProcessorInterface, userIdProvider: UserIdProvider, platform: String) {
        self.storage = storage
        self.requestProcessor = requestProcessor
        self.userIdProvider = userIdProvider
        self.platform = platform
    }

    /// Fails soft, one report at a time. A report the backend answered — with
    /// any status, including "no such endpoint" — is dropped: retrying it
    /// forever against a 404 is how the ObjC implementation filled the disk.
    /// Only a transport failure keeps it for the next launch.
    func sendStoredReports() async {
        let reports: [CrashReport] = storage.all()
        guard !reports.isEmpty else { return }

        let userId: String = userIdProvider.getUserId()
        for report in reports {
            let body: RequestBodyDict = report.requestBody(userId: userId, platform: platform)
            let request = Request.sdkCrash(body: body)
            do {
                let _: EmptyApiResponse = try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
                storage.remove(report)
            } catch let error as QonversionError where error.type != .invalidResponse {
                // The backend answered (even to reject): delivered as far as
                // this queue is concerned.
                storage.remove(report)
            } catch {
                // No response at all — keep it for the next launch.
                return
            }
        }
    }
}
