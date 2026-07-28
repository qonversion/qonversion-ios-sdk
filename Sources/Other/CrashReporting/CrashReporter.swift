//
//  CrashReporter.swift
//  Qonversion
//

import Foundation

/// Reports crashes raised inside the SDK itself.
///
/// NSException only, deliberately the same scope as the ObjC SDK: signal and
/// Mach handlers belong to the host app's own crash reporter, so real crashes
/// (SIGSEGV, a Swift runtime trap) are not captured here.
///
/// Reports go to the sdk-logs service on the launch after the crash, never to
/// the main API — see ``CrashReportsTransport``. Nothing about the send ever
/// reaches the host.
// @unchecked: the installed state is lock-guarded and the C handler captures nothing.
final class CrashReporter: @unchecked Sendable {

    /// The C exception handler cannot capture context, so the reporter has to
    /// be reachable statically.
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

    /// Runs while the process is dying: stays synchronous, and calls the
    /// previous handler whatever happens here.
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

/// Ships the reports the previous launch left behind to the sdk-logs service.
struct CrashReportsSender {

    private let storage: CrashReportsStorage
    private let transport: CrashReportsTransportInterface
    private let userIdProvider: UserIdProvider
    private let userManager: UserManagerInterface
    private let device: SdkLogDevice

    init(storage: CrashReportsStorage, transport: CrashReportsTransportInterface, userIdProvider: UserIdProvider, userManager: UserManagerInterface, device: SdkLogDevice) {
        self.storage = storage
        self.transport = transport
        self.userIdProvider = userIdProvider
        self.userManager = userManager
        self.device = device
    }

    /// Attempt budget per report: a payload the service keeps refusing would
    /// otherwise hold a slot and one POST per launch forever.
    static var maxSendAttempts: Int { 5 }

    /// Fails soft, one report at a time. The service answers with nothing this
    /// SDK can read, so the only verdicts are delivered and not delivered.
    func sendStoredReports() async {
        let reports: [CrashReport] = storage.all()
        guard !reports.isEmpty else { return }

        // A crash on the first launch is reported before the user exists, and
        // the uid on the envelope would be one the backend has never seen.
        do {
            try await userManager.obtainUser()
        } catch {
            return
        }

        // The uid is only knowable once the gate above has run.
        let device: SdkLogDevice = device.withUid(userIdProvider.getUserId())
        for report in reports {
            switch await transport.send(body: report.requestBody(device: device)) {
            case .delivered:
                storage.remove(report)
            case .rejected:
                countAttempt(of: report)
            case .notReached:
                // The network is the problem, not this report: it keeps its
                // budget, and the rest of the queue keeps its launch.
                return
            }
        }
    }

    /// Gives up on the report once it has burned its attempt budget.
    private func countAttempt(of report: CrashReport) {
        let attempted: CrashReport = report.countingSendAttempt()
        if attempted.sendAttempts >= Self.maxSendAttempts {
            storage.remove(report)
        } else {
            storage.replace(report, with: attempted)
        }
    }
}
