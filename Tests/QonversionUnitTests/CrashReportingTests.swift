//
//  CrashReportingTests.swift
//  QonversionUnitTests
//
//  The SDK reports its OWN crashes and nothing else. The filtering decision is
//  a pure function over callStackSymbols, so it is pinned directly; the
//  storage bound and the send-on-launch flow are pinned over the real storage
//  and the stub network layer.
//

import XCTest
@testable import Qonversion

final class CrashReportFilterTests: XCTestCase {

    private let appName = "MyApp"

    private func frame(_ index: Int, _ image: String, _ symbol: String) -> String {
        return "\(index)   \(image)                        0x000000010a2b3c4d \(symbol) + 42"
    }

    // MARK: - the SDK as its own image (framework / CocoaPods)

    func testAFrameworkFrameIsRecognized() {
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, "Qonversion", "$s10Qonversion15PurchasesManagerC8purchaseyyF"),
            frame(2, appName, "main")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .framework)
    }

    // MARK: - the SDK inside the host executable (SPM)

    func testAMangledSwiftSymbolInTheHostExecutableIsRecognized() {
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, appName, "$s10Qonversion15PurchasesManagerC8purchaseyyF")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .spm)
    }

    func testAHostFrameThatMerelyMentionsAnSdkTypeIsNotOurs() {
        // The hostile shape: the app's own frame, whose only connection to the
        // SDK is a parameter type. Matching the demangled "Qonversion." would
        // ship this app's crashes to us.
        let symbols: [String] = [
            frame(0, appName, "MyApp.PaywallViewController.show(product: Qonversion.Product) -> ()"),
            frame(1, appName, "main")
        ]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName))
    }

    func testAHostFrameReturningAnSdkTypeIsNotOurs() {
        let symbols: [String] = [frame(0, appName, "$s5MyApp5StoreC8products10QonversionAA7ProductVSayAEGyF")]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName),
                     "the SDK module is not the DECLARING module of this frame")
    }

    func testAnObjCEraSymbolIsStillRecognized() {
        let symbols: [String] = [frame(0, appName, "-[QONNoCodesViewController viewDidLoad]")]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .spm)
    }

    // MARK: - everything else is the app's business

    func testAPureHostAppCrashIsNotOurs() {
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, appName, "$s5MyApp14LoginViewModelC5loginyyF"),
            frame(2, appName, "main")
        ]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName))
    }

    func testAnotherVendorsFrameworkIsNotOurs() {
        let symbols: [String] = [frame(0, "SomeAnalytics", "-[SAEventTracker track:]")]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName))
    }

    func testTheWholeStackIsScanned() {
        // The ObjC implementation returned NO at the first app frame whose
        // symbol did not match, which misses every SDK frame below an app
        // frame — the common case, since the app is what calls in.
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, appName, "$s5MyApp14LoginViewModelC5loginyyF"),
            frame(2, appName, "$s10Qonversion15PurchasesManagerC8purchaseyyF"),
            frame(3, appName, "main")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .spm,
                       "an SDK frame below an app frame must still be found")
    }

    func testAnExplicitSdkImageWinsOverAHostExecutableMatch() {
        // The only input shape where .spm and .framework genuinely compete:
        // frame 0 is an SDK frame folded into the host executable (a MANGLED
        // symbol — the demangled form is deliberately not a marker), and a
        // later frame carries the SDK's own image, which is the more precise
        // answer.
        let symbols: [String] = [
            frame(0, appName, "$s10Qonversion15PurchasesManagerC8purchaseyyF"),
            frame(1, "Qonversion", "$s10Qonversion15PurchasesManagerC8purchaseyyF")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .framework)
    }

    func testAnEmptyStackIsNotOurs() {
        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: [], appExecutableName: appName))
    }

    func testAMalformedFrameIsSkippedInsteadOfCrashing() {
        let symbols: [String] = ["", "0", frame(1, "Qonversion", "$s10Qonversion1AC1byyF")]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .framework)
    }

    func testTheImageNameIsTheSecondField() {
        XCTAssertEqual(CrashReportFilter.imageName(ofFrame: frame(3, "Qonversion", "sym")), "Qonversion")
        XCTAssertNil(CrashReportFilter.imageName(ofFrame: "onlyonefield"))
    }

    // MARK: - binary image names containing a space

    func testAnImageNameContainingASpaceIsReadWhole() {
        // An app whose executable is "My App" is ordinary on the App Store.
        // Taking the second whitespace-separated field truncates it to "My",
        // which matches nothing — every SDK crash in such an app is then
        // classified "not ours" and silently never reported.
        XCTAssertEqual(CrashReportFilter.imageName(ofFrame: frame(3, "My App", "sym")), "My App")
    }

    func testASpacedHostExecutableStillMatchesAnSpmFrame() {
        let spacedAppName = "My App"
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, spacedAppName, "$s10Qonversion15PurchasesManagerC8purchaseyyF")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: spacedAppName), .spm)
    }

    func testAnAppWhoseNameStartsWithTheSdkImageNameIsNotTheSdk() {
        // "Qonversion Demo" is an ordinary name for a sample or companion app.
        // Reading only the second whitespace-separated field turns its image
        // name into exactly "Qonversion", so every crash of that app would be
        // classified as the SDK's own and shipped to us — the app's private
        // stack included.
        let sdkLikeAppName = "Qonversion Demo"
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, sdkLikeAppName, "$s15QonversionDemo14LoginViewModelC5loginyyF"),
            frame(2, sdkLikeAppName, "main")
        ]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: sdkLikeAppName),
                     "the image is the app, not the SDK — only reading the name whole can tell")
    }

    func testAnImageNameIsNotMatchedByItsTruncatedPrefix() {
        // The host executable is "My", and a DIFFERENT image called "My App"
        // (a bundled helper framework) carries the SDK frame. Truncating the
        // image name to its first field makes the two indistinguishable, and
        // the frame is attributed to the host executable that never ran it.
        let symbols: [String] = [frame(0, "My App", "$s10Qonversion15PurchasesManagerC8purchaseyyF")]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: "My"),
                     "\"My App\" is not the host executable \"My\"")
    }
}

// MARK: - persistence

final class CrashReportsStorageTests: XCTestCase {

    private var storage: CrashReportsStorage!
    private var localStorage: LocalStorage!

    override func setUp() {
        super.setUp()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        localStorage = LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: encoder, decoder: decoder)
        storage = CrashReportsStorage(localStorage: localStorage)
    }

    override func tearDown() {
        storage = nil
        localStorage = nil
        super.tearDown()
    }

    private func makeReport(id: String = UUID().uuidString, name: String = "NSInvalidArgumentException") -> CrashReport {
        return CrashReport(
            id: id,
            name: name,
            reason: "-[NSNull length]: unrecognized selector sent to instance",
            stackTrace: ["0   Qonversion   0x01 sym + 1"],
            linkage: .spm,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            sdkVersion: "6.0.0"
        )
    }

    func testAStoredReportSurvivesTheRoundTrip() throws {
        let report: CrashReport = makeReport(id: "r1")

        storage.store(report)

        let restored = try XCTUnwrap(CrashReportsStorage(localStorage: localStorage).all().first)
        XCTAssertEqual(restored, report, "every field must survive: the report is useless half-decoded")
    }

    func testTheQueueIsBoundedAndKeepsTheNewest() {
        let overflow: Int = CrashReportsStorage.maxStoredReports + 3

        for index in 0..<overflow {
            storage.store(makeReport(id: "r\(index)"))
        }

        let stored: [String] = storage.all().map { $0.id }
        XCTAssertEqual(stored.count, CrashReportsStorage.maxStoredReports)
        XCTAssertEqual(stored.first, "r3", "the oldest is dropped first")
        XCTAssertEqual(stored.last, "r\(overflow - 1)")
    }

    func testRemoveDeletesTheGivenReportOnly() {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))

        storage.remove(makeReport(id: "r1"))

        XCTAssertEqual(storage.all().map { $0.id }, ["r2"])
    }

    func testAReportStoredByAnOlderBuildDecodesWithNoAttemptsSpent() throws {
        // The first launch after the upgrade is the one that still holds the
        // crash evidence from before it. A stored report written without the
        // attempt counter must decode, not throw — a throw here empties the
        // whole queue, because the array is decoded as a whole.
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        let legacyPayload: String = """
        [{"id":"legacy","name":"NSInvalidArgumentException","reason":"boom",\
        "stackTrace":["0 Qonversion 0x01 sym + 1"],"linkage":"spm",\
        "occurredAt":"2023-11-14T22:13:20Z","sdkVersion":"6.0.0"}]
        """
        defaults.set(Data(legacyPayload.utf8), forKey: "qonversion.keys.crashReports")
        let legacyStorage = CrashReportsStorage(localStorage: LocalStorage(userDefaults: defaults, encoder: encoder, decoder: decoder))

        let restored: CrashReport = try XCTUnwrap(legacyStorage.all().first)

        XCTAssertEqual(restored.id, "legacy")
        XCTAssertEqual(restored.sendAttempts, 0, "an old report has spent none of its budget")
    }

    func testReplaceSwapsTheReportInPlaceAndResurrectsNothing() throws {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))

        storage.replace(makeReport(id: "r1"), with: makeReport(id: "r1").countingSendAttempt())
        storage.replace(makeReport(id: "gone"), with: makeReport(id: "gone").countingSendAttempt())

        XCTAssertEqual(storage.all().map { $0.id }, ["r1", "r2"])
        XCTAssertEqual(storage.all().map { $0.sendAttempts }, [1, 0])
    }

    func testTheRequestBodyMatchesTheProposedContract() throws {
        let body: RequestBodyDict = makeReport(id: "r1").requestBody(userId: "QON_u", platform: "iOS")

        XCTAssertEqual(body["sdk_version"] as? String, "6.0.0")
        XCTAssertEqual(body["platform"] as? String, "iOS")
        XCTAssertEqual(body["user_id"] as? String, "QON_u")
        XCTAssertEqual(body["occurred_at"] as? Int, 1_700_000_000)
        let exception = try XCTUnwrap(body["exception"] as? RequestBodyDict)
        XCTAssertEqual(exception["name"] as? String, "NSInvalidArgumentException")
        XCTAssertEqual(exception["linkage"] as? String, "spm")
        XCTAssertEqual((exception["stack_trace"] as? RequestBodyArray)?.count, 1)
    }
}

// MARK: - the handler and the send on the next launch

final class CrashReporterTests: XCTestCase {

    private var localStorage: LocalStorage!
    private var storage: CrashReportsStorage!

    override func setUp() {
        super.setUp()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        localStorage = LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: encoder, decoder: decoder)
        storage = CrashReportsStorage(localStorage: localStorage)
    }

    override func tearDown() {
        CrashReporter.shared.uninstall()
        storage = nil
        localStorage = nil
        super.tearDown()
    }

    private func makeException(symbols: [String]) -> NSException {
        // NSException.callStackSymbols is populated by @throw, not by init, so
        // the handler is driven with a stubbed subclass instead of raising a
        // real exception inside the test process.
        return StubbedStackException(name: .invalidArgumentException, reason: "boom", stackSymbols: symbols)
    }

    func testAnSdkExceptionIsStored() {
        CrashReporter.shared.install(storage: storage, appExecutableName: "MyApp")
        let exception = makeException(symbols: ["0   Qonversion   0x01 $s10Qonversion1AC1byyF + 1"])

        CrashReporter.shared.handle(exception)

        let stored = storage.all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, NSExceptionName.invalidArgumentException.rawValue)
        XCTAssertEqual(stored.first?.reason, "boom")
        XCTAssertEqual(stored.first?.linkage, .framework)
    }

    func testAHostAppExceptionIsNotStored() {
        CrashReporter.shared.install(storage: storage, appExecutableName: "MyApp")
        let exception = makeException(symbols: ["0   MyApp   0x01 $s5MyApp1AC1byyF + 1"])

        CrashReporter.shared.handle(exception)

        XCTAssertTrue(storage.all().isEmpty, "the app's own crashes are the app's business")
    }

    func testAnExceptionWithoutAReasonGetsTheDefaultOne() {
        CrashReporter.shared.install(storage: storage, appExecutableName: "MyApp")
        let exception = StubbedStackException(name: .genericException, reason: nil, stackSymbols: ["0   Qonversion   0x01 sym + 1"])

        CrashReporter.shared.handle(exception)

        XCTAssertEqual(storage.all().first?.reason, CrashReport.unknownReason)
    }

    func testThePreviousHandlerIsChained() {
        // Installing the SDK must never cost the host its own crash reporter.
        PreviousHandlerSpy.reset()
        NSSetUncaughtExceptionHandler { exception in
            PreviousHandlerSpy.record(exception.name.rawValue)
        }
        CrashReporter.shared.install(storage: storage, appExecutableName: "MyApp")

        CrashReporter.shared.handle(makeException(symbols: ["0   Qonversion   0x01 sym + 1"]))

        XCTAssertEqual(PreviousHandlerSpy.captured(), [NSExceptionName.invalidArgumentException.rawValue])
    }

    func testThePreviousHandlerIsChainedEvenForAForeignException() {
        PreviousHandlerSpy.reset()
        NSSetUncaughtExceptionHandler { exception in
            PreviousHandlerSpy.record(exception.name.rawValue)
        }
        CrashReporter.shared.install(storage: storage, appExecutableName: "MyApp")

        CrashReporter.shared.handle(makeException(symbols: ["0   MyApp   0x01 sym + 1"]))

        XCTAssertEqual(PreviousHandlerSpy.captured().count, 1, "the host's handler runs whether or not the SDK claimed the exception")
    }

    // MARK: - send on the next launch

    private func makeSender(processor: RequestProcessorInterface) -> CrashReportsSender {
        let userIdProvider = InternalConfig(userId: "QON_u")

        return CrashReportsSender(
            storage: storage,
            requestProcessor: processor,
            userIdProvider: userIdProvider,
            platform: "iOS"
        )
    }

    private func makeReport(id: String) -> CrashReport {
        return CrashReport(id: id, name: "NSInvalidArgumentException", reason: "boom", stackTrace: ["0 Qonversion 0x01 sym + 1"], linkage: .spm)
    }

    func testStoredReportsAreSentAndDropped() async {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse(), EmptyApiResponse()]

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(processor.processedRequests.count, 2)
        guard case let .sdkCrash(endpoint, body, type) = processor.processedRequests[0] else {
            return XCTFail("Expected an .sdkCrash request")
        }
        XCTAssertEqual(endpoint, "v4/sdk-crashes")
        XCTAssertEqual(type, .post)
        XCTAssertEqual(body["user_id"] as? String, "QON_u")
        XCTAssertTrue(storage.all().isEmpty, "a delivered report is not sent again")
    }

    func testAnEmptyQueueSendsNothing() async {
        let processor = MockRequestProcessor()

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertTrue(processor.processedRequests.isEmpty)
    }

    func testARevokedProjectKeyKeepsTheReportForTheNextLaunch() async {
        // .critical is thrown by the revoked-key latch BEFORE the request ever
        // leaves the device, so it says nothing about the report. Treating it
        // as "the backend answered" destroys every stored report on one launch.
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        processor.error = QonversionError(type: .critical)

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "nothing was ever sent — the report is not delivered")
    }

    func testAThrottledSendKeepsTheReportForTheNextLaunch() async {
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        processor.error = QonversionError(type: .rateLimitExceeded)

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "the rate limiter refused to send it, the backend never saw it")
    }

    func testAnErrorWithoutAnHttpStatusKeepsTheReport() async {
        // Nothing here proves the backend saw the report: a status-less
        // failure is raised before the request leaves the device (a bad URL,
        // the latch, the local limiter) or by transport. Deleting on the
        // semantic type alone is what makes such a failure lose crash reports.
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        processor.error = QonversionError(type: .invalidRequest)

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "no status, no proof of delivery")
    }

    func testAConnectionFailureKeepsTheReportForTheNextLaunch() async {
        // .networkConnectionFailed is the network layer's name for a request
        // that never reached the backend. It is the most ordinary way a crash
        // report's send fails — the user who crashed was offline — so it must
        // fall to the KEEP default, never to the drop set.
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        let connectionError: QonversionError = QonversionError(type: .networkConnectionFailed, error: URLError(.notConnectedToInternet))
        processor.error = connectionError

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "the request never reached the backend — the report is not delivered")
    }

    func testAKeptReportStopsTheLaunchInsteadOfBurningTheWholeQueue() async {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))
        let processor = MockRequestProcessor()
        processor.error = QonversionError(type: .critical)

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(processor.processedRequests.count, 1, "one refusal is enough to know the rest will be refused too")
        XCTAssertEqual(storage.all().map { $0.id }, ["r1", "r2"])
    }

    func testATransportFailureKeepsTheReportForTheNextLaunch() async {
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        processor.error = QonversionError(type: .invalidResponse, error: URLError(.notConnectedToInternet))

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"])
    }

    func testSendingNeverThrowsAtTheCaller() async {
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed

        // No `try`: the API itself guarantees the host is never bothered.
        await makeSender(processor: processor).sendStoredReports()

        XCTAssertNotNil(storage.all().first)
    }

    // MARK: - the answers the real network layer actually produces
    //
    // The classification lives or dies on what a QonversionError CARRIES, not
    // on what a hand-built one is labelled with. Every case below is driven
    // through the real RequestProcessor and the real NetworkErrorHandler, so
    // the type and the status are the ones production would see.

    private func makeRealProcessor(networkProvider: MockNetworkProvider) -> RequestProcessor {
        let responseDecoder = ResponseDecoder(decoder: JSONDecoder())
        let criticalErrorCodes: [ResponseCode] = [.unauthorized, .paymentRequired, .forbidden]
        let networkErrorHandler = NetworkErrorHandler(criticalErrorCodes: criticalErrorCodes, decoder: responseDecoder)

        return RequestProcessor(
            baseURL: "https://api.qonversion.io/",
            networkProvider: networkProvider,
            headersBuilder: MockHeadersBuilder(),
            errorHandler: networkErrorHandler,
            decoder: responseDecoder,
            retriableRequestKinds: [],
            requestsStorage: MockRequestsStorage(),
            rateLimiter: MockRateLimiter(),
            // The backoff is proven elsewhere; waiting it out here would only
            // make the suite slow.
            transportRetryDelayCeiling: 0
        )
    }

    private func makeCrashResponse(statusCode: Int) -> HTTPURLResponse {
        let url = URL(string: "https://api.qonversion.io/v4/sdk-crashes")!

        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func makeNetworkProvider(statusCode: Int, body: Data = Data()) -> MockNetworkProvider {
        let networkProvider = MockNetworkProvider()
        networkProvider.response = makeCrashResponse(statusCode: statusCode)
        networkProvider.responseData = body

        return networkProvider
    }

    func testAnUnroutedGatewayNotFoundDropsTheReport() async {
        // The motivating shape: `POST v4/sdk-crashes` does not exist yet, so
        // the gateway answers 404 with no application error envelope at all.
        // There is no `not_found` slug to classify it, so it arrives as
        // .unknown — deleting only on .resourceNotFound leaves the queue
        // pinned forever, one wasted POST per launch.
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 404, body: Data("<html><body>404 Not Found</body></html>".utf8))

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(storage.all().isEmpty, "the gateway answered 404 — resending it every launch changes nothing")
    }

    func testAMalformedRequestRejectionDropsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let body = Data(#"{"error": {"type": "request", "code": "invalid_data", "message": "bad body"}}"#.utf8)
        let networkProvider = makeNetworkProvider(statusCode: 400, body: body)

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(storage.all().isEmpty, "the body will be just as invalid next launch")
    }

    func testAServerFailureFromTheBackendKeepsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 500)

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "5xx means the backend did not process it")
    }

    func testAnOfflineSendKeepsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = URLError(.notConnectedToInternet)

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "no answer at all is not a rejection")
    }

    func testARevokedKeyStatusKeepsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 401)

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "the key is the problem, not the report")
    }

    func testAThrottlingStatusKeepsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 429)

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "429 is a 4xx that says come back later")
    }

    // MARK: - one bad report must not starve the queue

    func testAPerReportRejectionDoesNotStarveTheRestOfTheQueue() async {
        // The first report is poison — the backend chokes on it every time.
        // Stopping the launch there means the healthy second report is never
        // sent, on this launch or any other.
        storage.store(makeReport(id: "poison"))
        storage.store(makeReport(id: "healthy"))
        let networkProvider = MockNetworkProvider()
        networkProvider.responseData = Data()
        networkProvider.response = makeCrashResponse(statusCode: 500)
        networkProvider.onSend = { [weak networkProvider] in
            guard let networkProvider else { return }
            let isFirstSend: Bool = networkProvider.sentRequests.count == 1
            networkProvider.response = self.makeCrashResponse(statusCode: isFirstSend ? 500 : 204)
        }

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(networkProvider.sentRequests.count, 2, "the second report deserved its own attempt")
        XCTAssertEqual(storage.all().map { $0.id }, ["poison"], "the healthy report was delivered and dropped")
    }

    func testAReportTheBackendKeepsRejectingIsEventuallyGivenUpOn() async {
        // A payload the service chokes on answers the same way every launch.
        // Without a budget it would hold one of the five slots and one POST per
        // launch for the lifetime of the install.
        storage.store(makeReport(id: "poison"))
        let networkProvider = makeNetworkProvider(statusCode: 500)

        for launch in 1..<CrashReportsSender.maxSendAttempts {
            await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

            XCTAssertEqual(storage.all().map { $0.sendAttempts }, [launch], "launch \(launch) counts against the budget")
        }
        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(storage.all().isEmpty, "the budget is spent — the slot goes back to the reports that can be delivered")
    }

    func testAnOfflineLaunchDoesNotBurnTheAttemptBudget() async {
        // A user who is offline for a week must not lose the crash report that
        // week: the failures say nothing about the report, so they cost it
        // nothing.
        storage.store(makeReport(id: "r1"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = URLError(.notConnectedToInternet)

        for _ in 0...CrashReportsSender.maxSendAttempts {
            await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()
        }

        XCTAssertEqual(storage.all().map { $0.sendAttempts }, [0], "only an answer from the backend costs an attempt")
    }

    func testAnEnvironmentWideFailureStopsTheLaunch() async {
        // Offline is not the report's fault and not the report's problem:
        // every following send would fail the same way, so trying them is
        // pure waste.
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = URLError(.notConnectedToInternet)

        await makeSender(processor: makeRealProcessor(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(networkProvider.sentRequests.count, RequestProcessor.maxTransportRetries + 1,
                       "one report's worth of transport retries, then the launch gives up")
        XCTAssertEqual(storage.all().map { $0.id }, ["r1", "r2"])
    }
}

/// NSException populates callStackSymbols only when it is actually thrown;
/// this stands in for a thrown one.
private final class StubbedStackException: NSException {

    private let stackSymbols: [String]

    init(name: NSExceptionName, reason: String?, stackSymbols: [String]) {
        self.stackSymbols = stackSymbols
        super.init(name: name, reason: reason, userInfo: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var callStackSymbols: [String] {
        return stackSymbols
    }
}

/// A stand-in for the host app's own crash reporter.
// @unchecked: the array is lock-guarded; the storage is static because a C
// exception handler cannot capture anything.
final class PreviousHandlerSpy: @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: [String] = []

    static func reset() {
        lock.lock()
        names = []
        lock.unlock()
    }

    static func record(_ name: String) {
        lock.lock()
        names.append(name)
        lock.unlock()
    }

    static func captured() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }
}
