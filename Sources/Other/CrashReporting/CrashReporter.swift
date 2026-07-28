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
/// `POST v4/sdk-crashes` does not exist yet, so every failure path leaves the
/// report queued and nothing ever reaches the host.
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

    /// Attempt budget per report: a payload the backend keeps refusing would
    /// otherwise hold a slot and one POST per launch forever.
    static var maxSendAttempts: Int { 5 }

    /// Fails soft, one report at a time; ``outcome(for:)`` decides each verdict.
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
            } catch {
                switch Self.outcome(for: error) {
                case .drop:
                    storage.remove(report)
                case .keepAndStop:
                    return
                case .keepAndContinue:
                    countAttempt(of: report)
                }
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

    /// What to do with a report whose send failed.
    enum SendOutcome {
        /// A resend cannot change the answer — stop wasting a launch on it.
        case drop
        /// The failure is about this report; the next one is still worth a try.
        case keepAndContinue
        /// The failure is about the environment, so every following send would
        /// fail the same way.
        case keepAndStop
    }

    /// Classifies a failed send by the HTTP status carried on the error, not by
    /// the error type: the endpoint is unrouted today, and an unrouted path
    /// answers a bare 404 with no error envelope, which arrives as `.unknown`.
    /// A status-less failure defaults to keep.
    static func outcome(for error: Error) -> SendOutcome {
        // Cancellation is a mid-flight user switch: nothing was decided here,
        // and the next send would be cancelled too.
        guard !error.isCancellation else { return .keepAndStop }
        guard let qonversionError = error as? QonversionError else { return .keepAndStop }

        switch qonversionError.type {
        // Raised before the request leaves the device, by state that applies to
        // every report equally.
        case .critical, .rateLimitExceeded:
            return .keepAndStop
        default:
            break
        }

        guard let statusCode: Int = qonversionError.additionalInfo?[ErrorConstants.statusCodeKey.rawValue] as? Int else {
            // No status, no verdict. `.invalidResponse` also arrives from a 2xx
            // whose body failed to decode, so keeping can resend a report the
            // backend took — deliberate: a duplicate costs less than a loss.
            return .keepAndStop
        }

        // The key or the project is the problem, for every report equally.
        if Self.environmentWideStatusCodes.contains(statusCode) {
            return .keepAndStop
        }
        // The backend refused this report itself; a next launch changes nothing.
        if Self.clientErrorRange.contains(statusCode) {
            return .drop
        }

        // Answered but did not take it (5xx): reachable, so the next report is
        // worth a try, and this one's attempt is counted.
        return .keepAndContinue
    }

    /// ``ResponseCode`` does not name it because no other caller branches on it.
    private static let tooManyRequestsStatusCode: Int = 429

    /// Environment-wide 4xx — the revoked-key latch (401/402/403) and the
    /// throttle (429) — carved out of the delete range below.
    private static let environmentWideStatusCodes: Set<Int> = [
        ResponseCode.unauthorized.rawValue,
        ResponseCode.paymentRequired.rawValue,
        ResponseCode.forbidden.rawValue,
        tooManyRequestsStatusCode
    ]

    private static let clientErrorRange: ClosedRange<Int> = 400...499
}
