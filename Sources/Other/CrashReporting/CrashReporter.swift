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

    /// How many times one report may be kept by a backend that answered before
    /// it is given up on. A payload the service chokes on would otherwise sit
    /// in the queue forever, taking one of the five slots and one POST per
    /// launch from the reports that could still be delivered.
    static var maxSendAttempts: Int { 5 }

    /// Fails soft, one report at a time.
    ///
    /// Three outcomes per report, see ``outcome(for:)``: delivered or
    /// permanently rejected → dropped; rejected in a way that is about THIS
    /// report → kept, its attempt counted, and the queue continues; rejected in
    /// a way that is about the environment → kept and the launch stops, because
    /// every following send would hit the same wall.
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

    /// Records that the backend answered and kept this report, and gives up on
    /// it once it has burned its budget.
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
        /// The failure is about the environment: the key, the connection, the
        /// throttle. Every following send would fail the same way.
        case keepAndStop
    }

    /// Classifies a failed send by what the failure actually CARRIES, not by
    /// the semantic type alone.
    ///
    /// The type is not enough on its own. `POST v4/sdk-crashes` DOES NOT EXIST
    /// YET (see ``CrashReporter``): an API gateway answers an unrouted path
    /// with a bare 404 and no application error envelope, so there is no
    /// `not_found` slug for ``NetworkErrorHandler`` to read and the error
    /// arrives as `.unknown` — the same type an unrecognized 4xx gets. Deleting
    /// only on `.resourceNotFound` would leave that queue pinned forever, one
    /// wasted POST per launch. The HTTP status is on the error already:
    /// ``NetworkErrorHandler`` puts it in `additionalInfo` under
    /// ``ErrorConstants/statusCodeKey`` for every answer the backend gives.
    ///
    /// The default stays KEEP. A status-less failure proves nothing about the
    /// report — it was raised before the request left the device (`.critical`
    /// from the revoked-key latch, `.rateLimitExceeded` from the local limiter,
    /// `.invalidRequest` from a URL that would not build) or by transport — and
    /// dropping on those destroys every stored report on a single launch. The
    /// queue is hard-bounded at ``CrashReportsStorage/maxStoredReports``, so
    /// keeping is cheap and losing a crash report is not.
    static func outcome(for error: Error) -> SendOutcome {
        // Cancellation is the SDK switching users mid-flight: nothing was
        // decided about the report, and the next send would be cancelled too.
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
            // No status means no verdict on the report: transport, the latch,
            // the limiter, a request that never built.
            //
            // `.invalidResponse` lands here from BOTH of its producers, and the
            // second one is not transport: a 2xx whose body failed to decode
            // (``RequestProcessor``) — a captive portal or a CDN answering 200
            // with HTML. The backend may in fact have accepted the report, so
            // keeping it can duplicate it on the next launch. That is the
            // deliberate trade: an unproven delivery is resent, because losing
            // a crash report costs more than a duplicate the backend dedupes.
            return .keepAndStop
        }

        // The key or the project is the problem, and it is the problem for
        // every report — including the ones a fixed key could still deliver.
        if Self.environmentWideStatusCodes.contains(statusCode) {
            return .keepAndStop
        }
        // The backend refused the report itself: a bad route, a body it will
        // not accept, a payload too large. Next launch changes none of that.
        if Self.clientErrorRange.contains(statusCode) {
            return .drop
        }

        // The backend answered but did not take it (5xx, or anything else
        // outside 2xx). It was reachable, so the next report is worth a try —
        // and this one's attempt is counted, so a payload the service chokes on
        // cannot live in the queue forever.
        return .keepAndContinue
    }

    /// Throttling. ``ResponseCode`` does not name it because no other caller
    /// branches on it; ``RequestProcessor/isRetriableStatusCode(_:)`` uses the
    /// same literal for the same reason.
    private static let tooManyRequestsStatusCode: Int = 429

    /// 401/402/403 drive the revoked-key latch and 429 the throttle: all four
    /// describe the environment, not the report, and all four are 4xx — which
    /// is why they have to be carved out of the delete range below.
    private static let environmentWideStatusCodes: Set<Int> = [
        ResponseCode.unauthorized.rawValue,
        ResponseCode.paymentRequired.rawValue,
        ResponseCode.forbidden.rawValue,
        tooManyRequestsStatusCode
    ]

    private static let clientErrorRange: ClosedRange<Int> = 400...499
}
