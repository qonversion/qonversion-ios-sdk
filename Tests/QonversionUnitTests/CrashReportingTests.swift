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

    func testADemangledSwiftSymbolInTheHostExecutableIsRecognized() {
        let symbols: [String] = [frame(0, appName, "Qonversion.PurchasesManager.purchase()")]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .spm)
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
        let symbols: [String] = [
            frame(0, appName, "Qonversion.PurchasesManager.purchase()"),
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
        return CrashReportsSender(
            storage: storage,
            requestProcessor: processor,
            userIdProvider: InternalConfig(userId: "QON_u"),
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

    func testAMissingEndpointDropsTheReportInsteadOfRetryingForever() async {
        // The endpoint is a proposal: until it exists every send is rejected,
        // and a queue that never drains is how the ObjC implementation filled
        // the user's disk.
        storage.store(makeReport(id: "r1"))
        let processor = MockRequestProcessor()
        processor.error = QonversionError(type: .resourceNotFound)

        await makeSender(processor: processor).sendStoredReports()

        XCTAssertTrue(storage.all().isEmpty, "the backend answered — the report is done")
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
