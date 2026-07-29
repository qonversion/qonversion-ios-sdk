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

    // MARK: - the NoCodes module

    func testANoCodesFrameworkFrameIsRecognized() {
        // NoCodes is a separate module and a separate framework product, and it
        // holds every piece of UIKit code in the SDK — the likeliest source of
        // an NSException anywhere in it.
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, "NoCodes", "$s7NoCodes21NoCodesViewControllerC11viewDidLoadyyF"),
            frame(2, appName, "main")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .framework)
    }

    func testAMangledNoCodesSymbolInTheHostExecutableIsRecognized() {
        let symbols: [String] = [
            frame(0, "CoreFoundation", "__exceptionPreprocess"),
            frame(1, appName, "$s7NoCodes21NoCodesViewControllerC11viewDidLoadyyF")
        ]

        XCTAssertEqual(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName), .spm)
    }

    func testAHostFrameThatMerelyMentionsANoCodesTypeIsNotOurs() {
        let symbols: [String] = [
            frame(0, appName, "MyApp.PaywallRouter.present(screen: NoCodes.Screen) -> ()"),
            frame(1, appName, "main")
        ]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: appName))
    }

    func testAnAppWhoseNameStartsWithTheNoCodesImageNameIsNotTheSdk() {
        let sdkLikeAppName = "NoCodes Demo"
        let symbols: [String] = [
            frame(0, sdkLikeAppName, "$s12NoCodesDemo14LoginViewModelC5loginyyF"),
            frame(1, sdkLikeAppName, "main")
        ]

        XCTAssertNil(CrashReportFilter.linkage(ofCallStackSymbols: symbols, appExecutableName: sdkLikeAppName))
    }
}

// MARK: - persistence

final class CrashReportsStorageTests: XCTestCase {

    private var storage: CrashReportsStorage!
    private var localStorage: LocalStorage!
    private var fileStore: CrashReportsFileStore!
    private var fileDirectory: URL!

    override func setUp() {
        super.setUp()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        localStorage = LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: encoder, decoder: decoder)
        fileDirectory = TestFileDirectory.makeIsolated()
        fileStore = CrashReportsFileStore(directory: fileDirectory, encoder: encoder, decoder: decoder)
        storage = CrashReportsStorage(localStorage: localStorage, fileStore: fileStore)
    }

    override func tearDown() {
        storage = nil
        localStorage = nil
        fileStore = nil
        TestFileDirectory.remove(fileDirectory)
        fileDirectory = nil
        super.tearDown()
    }

    // MARK: - the file mirror

    func testAStoredReportSurvivesUserDefaultsNeverReachingDisk() throws {
        // The write goes to cfprefsd asynchronously, and the process is killed
        // by abort() the moment the handler returns — the defaults copy can
        // simply never land. The file written synchronously from the handler is
        // what makes the report survive at all.
        storage.store(makeReport(id: "r1"))

        let lostDefaults = LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: JSONEncoder.qonversionTest, decoder: JSONDecoder.qonversionTolerantTest)
        let nextLaunch = CrashReportsStorage(localStorage: lostDefaults, fileStore: fileStore)

        XCTAssertEqual(nextLaunch.all().map { $0.id }, ["r1"], "the crash evidence must not depend on cfprefsd having flushed")
    }

    func testTheReportIsOnDiskBeforeStoreReturns() throws {
        storage.store(makeReport(id: "r1"))

        let contents: [URL] = try FileManager.default.contentsOfDirectory(at: fileDirectory, includingPropertiesForKeys: nil)
        XCTAssertFalse(contents.isEmpty, "nothing was written synchronously — a dying process leaves no second chance")
    }

    func testBothSourcesAreMergedWithoutDuplicates() throws {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))

        let merged: [String] = CrashReportsStorage(localStorage: localStorage, fileStore: fileStore).all().map { $0.id }

        XCTAssertEqual(merged, ["r1", "r2"], "the same report held by both sources is still one report")
    }

    func testARemovedReportIsGoneFromBothSources() throws {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))

        storage.remove(makeReport(id: "r1"))

        XCTAssertEqual(fileStore.read().map { $0.id }, ["r2"], "a delivered report must not come back from the file on the next launch")
        XCTAssertEqual(storage.all().map { $0.id }, ["r2"])
    }

    func testTheAttemptCounterIsPersistedToBothSources() throws {
        storage.store(makeReport(id: "r1"))

        storage.replace(makeReport(id: "r1"), with: makeReport(id: "r1").countingSendAttempt())

        XCTAssertEqual(fileStore.read().map { $0.sendAttempts }, [1], "a budget spent only in defaults would reset on every launch")
    }

    func testTheFileQueueIsBoundedTheSameWay() {
        for index in 0..<(CrashReportsStorage.maxStoredReports + 3) {
            storage.store(makeReport(id: "r\(index)"))
        }

        XCTAssertEqual(fileStore.read().count, CrashReportsStorage.maxStoredReports)
    }

    func testAStoreWithoutAWritableDirectoryStillUsesDefaults() {
        let disabled = CrashReportsFileStore(directory: nil, encoder: JSONEncoder.qonversionTest, decoder: JSONDecoder.qonversionTolerantTest)
        let storage = CrashReportsStorage(localStorage: localStorage, fileStore: disabled)

        storage.store(makeReport(id: "r1"))

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "an unavailable container must not cost the report entirely")
    }

    func testClearEmptiesBothSources() {
        storage.store(makeReport(id: "r1"))

        storage.clear()

        XCTAssertTrue(storage.all().isEmpty)
        XCTAssertTrue(fileStore.read().isEmpty)
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

        let restored = try XCTUnwrap(CrashReportsStorage(localStorage: localStorage, fileStore: fileStore).all().first)
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
        let legacyLocalStorage = LocalStorage(userDefaults: defaults, encoder: encoder, decoder: decoder)
        let legacyFileStore = CrashReportsFileStore(directory: nil, encoder: encoder, decoder: decoder)
        let legacyStorage = CrashReportsStorage(localStorage: legacyLocalStorage, fileStore: legacyFileStore)

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

    func testTheRequestBodyMatchesTheObjCSdkLogsEnvelope() throws {
        // The receiving service is the one the ObjC SDK has always shipped to,
        // and its envelope is the ObjC one, key for key.
        let body: RequestBodyDict = makeReport(id: "r1").requestBody(device: Self.device)

        XCTAssertEqual(Set(body.keys), ["device", "exception"])

        let device = try XCTUnwrap(body["device"] as? RequestBodyDict)
        XCTAssertEqual(Set(device.keys), ["platform", "platform_version", "source", "source_version", "project_key", "uid"])
        XCTAssertEqual(device["platform"] as? String, "iOS")
        XCTAssertEqual(device["platform_version"] as? String, "17.0")
        XCTAssertEqual(device["source"] as? String, "iOS")
        XCTAssertEqual(device["source_version"] as? String, "6.0.0")
        XCTAssertEqual(device["project_key"] as? String, "test-project-key")
        XCTAssertEqual(device["uid"] as? String, "QON_u")

        let exception = try XCTUnwrap(body["exception"] as? RequestBodyDict)
        XCTAssertEqual(exception["name"] as? String, "NSInvalidArgumentException")
        XCTAssertEqual(exception["message"] as? String, "-[NSNull length]: unrecognized selector sent to instance")
        XCTAssertEqual(exception["title"] as? String, "NSInvalidArgumentException: -[NSNull length]: unrecognized selector sent to instance")
        XCTAssertEqual(exception["rawStackTrace"] as? String, "0   Qonversion   0x01 sym + 1")
        XCTAssertEqual(exception["elements"] as? [String], ["0   Qonversion   0x01 sym + 1"])
        XCTAssertEqual(exception["isSpm"] as? Bool, true)
        XCTAssertEqual(exception["userInfo"] as? RequestBodyDict, [:])
        // Ours, carried inside the crash payload the service stores as-is.
        XCTAssertEqual(exception["sdk_version"] as? String, "6.0.0")
        XCTAssertEqual(exception["occurred_at"] as? Int, 1_700_000_000)
    }

    func testTheRawStackTraceJoinsTheFramesTheWayObjCDid() throws {
        let report = CrashReport(
            id: "r1",
            name: "NSRangeException",
            reason: "out of bounds",
            stackTrace: ["0 Qonversion 0x01 a + 1", "1 MyApp 0x02 b + 2"],
            linkage: .framework
        )

        let body: RequestBodyDict = report.requestBody(device: Self.device)

        let exception = try XCTUnwrap(body["exception"] as? RequestBodyDict)
        XCTAssertEqual(exception["rawStackTrace"] as? String, "0 Qonversion 0x01 a + 1\n1 MyApp 0x02 b + 2")
        XCTAssertEqual(exception["isSpm"] as? Bool, false)
    }

    static let device = SdkLogDevice(
        platform: "iOS",
        platformVersion: "17.0",
        source: "iOS",
        sourceVersion: "6.0.0",
        projectKey: "test-project-key",
        uid: "QON_u"
    )
}

// MARK: - the handler and the send on the next launch

final class CrashReporterTests: XCTestCase {

    private var localStorage: LocalStorage!
    private var storage: CrashReportsStorage!
    private var userManager: MockUserManager!
    private var gateCallsAtFirstRequest: Int = -1
    private var fileDirectory: URL!
    /// The handler the process had before this suite touched it. `uninstall()`
    /// only restores what `install()` found, which in these tests is a spy.
    private var originalExceptionHandler: (@convention(c) (NSException) -> Void)?

    override func setUp() {
        super.setUp()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        localStorage = LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: encoder, decoder: decoder)
        fileDirectory = TestFileDirectory.makeIsolated()
        let fileStore = CrashReportsFileStore(directory: fileDirectory, encoder: encoder, decoder: decoder)
        storage = CrashReportsStorage(localStorage: localStorage, fileStore: fileStore)
        userManager = MockUserManager()
        userManager.user = try? JSONDecoder.qonversionTest.decode(Qonversion.User.self, from: Data(#"{"id": "QON_u", "created_at": "2023-11-14T22:13:20Z"}"#.utf8))
        gateCallsAtFirstRequest = -1
        originalExceptionHandler = NSGetUncaughtExceptionHandler()
    }

    override func tearDown() {
        CrashReporter.shared.uninstall()
        NSSetUncaughtExceptionHandler(originalExceptionHandler)
        userManager = nil
        storage = nil
        localStorage = nil
        TestFileDirectory.remove(fileDirectory)
        fileDirectory = nil
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

    private func makeSender(transport: CrashReportsTransportInterface) -> CrashReportsSender {
        let userIdProvider = InternalConfig(userId: "QON_u")

        return CrashReportsSender(
            storage: storage,
            transport: transport,
            userIdProvider: userIdProvider,
            userManager: userManager,
            device: CrashReportsStorageTests.device
        )
    }

    /// The real transport over a stubbed socket: the URL, the method and the
    /// status handling are the ones production would use.
    private func makeTransport(networkProvider: MockNetworkProvider) -> CrashReportsTransport {
        return CrashReportsTransport(networkProvider: networkProvider)
    }

    private func makeNetworkProvider(statusCode: Int) -> MockNetworkProvider {
        let networkProvider = MockNetworkProvider()
        networkProvider.response = HTTPURLResponse(url: URL(string: "https://sdk-logs.qonversion.io/sdk.log")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        networkProvider.responseData = Data()

        return networkProvider
    }

    private func makeReport(id: String) -> CrashReport {
        return CrashReport(id: id, name: "NSInvalidArgumentException", reason: "boom", stackTrace: ["0 Qonversion 0x01 sym + 1"], linkage: .spm)
    }

    // MARK: - the target

    func testReportsGoToTheSdkLogsServiceNotTheApi() async throws {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 200)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        let request: URLRequest = try XCTUnwrap(networkProvider.sentRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sdk-logs.qonversion.io/sdk.log")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // The ObjC client sends Content-Type and nothing else: the project key
        // travels in the body, not in an Authorization header.
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testTheSentBodyCarriesTheDeviceEnvelopeAndTheCrashPayload() async throws {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 200)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        let body: Data = try XCTUnwrap(networkProvider.sentRequests.first?.httpBody)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(decoded.keys), ["device", "exception"])
        let device = try XCTUnwrap(decoded["device"] as? [String: Any])
        // The uid is the one the gate resolved, not the placeholder the
        // assembly built the envelope with.
        XCTAssertEqual(device["uid"] as? String, "QON_u")
        XCTAssertEqual(device["project_key"] as? String, "test-project-key")
        let exception = try XCTUnwrap(decoded["exception"] as? [String: Any])
        XCTAssertEqual(exception["name"] as? String, "NSInvalidArgumentException")
    }

    // MARK: - delivered or not, nothing in between

    func testStoredReportsAreSentAndDropped() async {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))
        let networkProvider = makeNetworkProvider(statusCode: 200)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(networkProvider.sentRequests.count, 2)
        XCTAssertTrue(storage.all().isEmpty, "a delivered report is not sent again")
    }

    func testAnyTwoHundredCountsAsDelivered() async {
        storage.store(makeReport(id: "r1"))
        // The service answers 204 as readily as 200, and its body is never
        // parsed — the status line is the whole verdict.
        let networkProvider = makeNetworkProvider(statusCode: 204)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(storage.all().isEmpty)
    }

    func testAnAnswerThatIsNotTwoHundredKeepsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 500)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"])
        XCTAssertEqual(storage.all().map { $0.sendAttempts }, [1], "the service saw it and refused — that costs an attempt")
    }

    func testAClientRejectionAlsoKeepsTheReportUntilItsBudgetIsSpent() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = makeNetworkProvider(statusCode: 400)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.sendAttempts }, [1])
    }

    func testAnOfflineSendKeepsTheReport() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = URLError(.notConnectedToInternet)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "no answer at all is not a rejection")
    }

    func testAnOfflineLaunchDoesNotBurnTheAttemptBudget() async {
        // A user offline for a week must not lose the crash report that week:
        // the failures say nothing about the report, so they cost it nothing.
        storage.store(makeReport(id: "r1"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = URLError(.notConnectedToInternet)

        for _ in 0...CrashReportsSender.maxSendAttempts {
            await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()
        }

        XCTAssertEqual(storage.all().map { $0.sendAttempts }, [0], "only an answer from the service costs an attempt")
    }

    func testAnUnreachableServiceStopsTheLaunch() async {
        // Every following send would fail the same way, so trying them is
        // pure waste.
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = URLError(.notConnectedToInternet)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(networkProvider.sentRequests.count, 1, "one failure is enough to know the network is down")
        XCTAssertEqual(storage.all().map { $0.id }, ["r1", "r2"])
    }

    // MARK: - the attempt budget

    func testAReportTheServiceKeepsRejectingIsEventuallyGivenUpOn() async {
        // A payload the service chokes on answers the same way every launch.
        // Without a budget it would hold one of the five slots and one POST per
        // launch for the lifetime of the install.
        storage.store(makeReport(id: "poison"))
        let networkProvider = makeNetworkProvider(statusCode: 500)

        for launch in 1..<CrashReportsSender.maxSendAttempts {
            await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

            XCTAssertEqual(storage.all().map { $0.sendAttempts }, [launch], "launch \(launch) counts against the budget")
        }
        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(storage.all().isEmpty, "the budget is spent — the slot goes back to the reports that can be delivered")
    }

    func testAPerReportRejectionDoesNotStarveTheRestOfTheQueue() async {
        // The first report is poison — the service chokes on it every time.
        // Stopping the launch there means the healthy second report is never
        // sent, on this launch or any other.
        storage.store(makeReport(id: "poison"))
        storage.store(makeReport(id: "healthy"))
        let networkProvider = makeNetworkProvider(statusCode: 500)
        networkProvider.onSend = { [weak networkProvider] in
            guard let networkProvider else { return }
            let isFirstSend: Bool = networkProvider.sentRequests.count == 1
            networkProvider.response = HTTPURLResponse(url: URL(string: "https://sdk-logs.qonversion.io/sdk.log")!, statusCode: isFirstSend ? 500 : 200, httpVersion: nil, headerFields: nil)!
        }

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(networkProvider.sentRequests.count, 2, "the second report deserved its own attempt")
        XCTAssertEqual(storage.all().map { $0.id }, ["poison"], "the healthy report was delivered and dropped")
    }

    // MARK: - the user gate

    func testTheUserGateIsPassedBeforeTheFirstReportIsSent() async {
        storage.store(makeReport(id: "r1"))
        storage.store(makeReport(id: "r2"))
        let networkProvider = makeNetworkProvider(statusCode: 200)
        networkProvider.onSend = { [weak self] in
            guard let self, self.gateCallsAtFirstRequest < 0 else { return }
            self.gateCallsAtFirstRequest = self.userManager.obtainUserCallsCount
        }

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertEqual(gateCallsAtFirstRequest, 1, "the backend user must exist before a report carries its uid")
        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "one gate pass per launch, not one per report")
        XCTAssertEqual(networkProvider.sentRequests.count, 2)
    }

    func testAFailingUserGateKeepsTheReportsForTheNextLaunch() async {
        storage.store(makeReport(id: "r1"))
        userManager.error = MockError.stubbed
        let networkProvider = makeNetworkProvider(statusCode: 200)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(networkProvider.sentRequests.isEmpty, "no report may be sent under a uid the backend does not have")
        XCTAssertEqual(storage.all().map { $0.id }, ["r1"], "a gate failure costs the report nothing")
    }

    func testAnEmptyQueueSendsNothing() async {
        let networkProvider = makeNetworkProvider(statusCode: 200)

        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertTrue(networkProvider.sentRequests.isEmpty)
    }

    func testSendingNeverThrowsAtTheCaller() async {
        storage.store(makeReport(id: "r1"))
        let networkProvider = MockNetworkProvider()
        networkProvider.error = MockError.stubbed

        // No `try`: the API itself guarantees the host is never bothered.
        await makeSender(transport: makeTransport(networkProvider: networkProvider)).sendStoredReports()

        XCTAssertNotNil(storage.all().first)
    }
}

// MARK: - the source the envelope reports

final class SdkLogDeviceTests: XCTestCase {

    private let deviceInfo = HeaderDeviceInfo(appVersion: "1.2.3", country: "US", language: "en", osName: "iOS", osVersion: "17.0")

    private func makeDevice(userDefaults: UserDefaults) -> SdkLogDevice {
        return SdkLogDevice.make(deviceInfo: deviceInfo, projectKey: "key", sdkVersion: "6.0.0", userDefaults: userDefaults)
    }

    func testTheNativeSdkReportsItselfAsTheSource() {
        let device: SdkLogDevice = makeDevice(userDefaults: TestDefaults.makeIsolated())

        XCTAssertEqual(device.source, "iOS")
        XCTAssertEqual(device.sourceVersion, "6.0.0")
    }

    func testACrossPlatformWrapperReportsItsOwnSource() {
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        defaults.set("flutter", forKey: "com.qonversion.keys.source")
        defaults.set("9.9.9", forKey: "com.qonversion.keys.sourceVersion")

        let device: SdkLogDevice = makeDevice(userDefaults: defaults)

        XCTAssertEqual(device.source, "flutter")
        XCTAssertEqual(device.sourceVersion, "9.9.9")
    }

    func testALeftoverVersionWithoutASourceIsIgnored() {
        // The Objective-C SDK persisted its own version under this key.
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        defaults.set("5.0.0", forKey: "com.qonversion.keys.sourceVersion")

        let device: SdkLogDevice = makeDevice(userDefaults: defaults)

        XCTAssertEqual(device.source, "iOS")
        XCTAssertEqual(device.sourceVersion, "6.0.0")
    }

    func testTheEnvelopeAgreesWithTheRequestHeaders() {
        // Two implementations of one resolution rule: the sdk-logs service
        // reads both, and they must never disagree.
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        defaults.set("react-native", forKey: "com.qonversion.keys.source")
        defaults.set("4.4.4", forKey: "com.qonversion.keys.sourceVersion")
        let collector = MockDeviceInfoCollector()
        let headersBuilder = HeadersBuilder(apiKey: "key", sdkVersion: "6.0.0", deviceInfoCollector: collector, userDefaults: defaults)
        var request = URLRequest(url: URL(string: "https://api2.qonversion.io/")!)
        headersBuilder.addHeaders(to: &request)

        let device: SdkLogDevice = SdkLogDevice.make(deviceInfo: collector.headerDeviceInfo(), projectKey: "key", sdkVersion: "6.0.0", userDefaults: defaults)

        XCTAssertEqual(device.source, request.value(forHTTPHeaderField: "Source"))
        XCTAssertEqual(device.sourceVersion, request.value(forHTTPHeaderField: "Source-Version"))
        XCTAssertEqual(device.platform, request.value(forHTTPHeaderField: "Platform"))
        XCTAssertEqual(device.platformVersion, request.value(forHTTPHeaderField: "Platform-Version"))
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

// MARK: - the proxy contract

/// `Configuration.proxyURL` is documented as redirecting ALL the requests from
/// the app to the API, and the README sells it for regions where the Qonversion
/// domains are unreachable. A transport that keeps its own hardcoded host
/// breaks both promises silently, and leaks project_key and uid while doing it.
final class CrashReportsTransportRoutingTests: XCTestCase {

    private func makeNetworkProvider() -> MockNetworkProvider {
        let networkProvider = MockNetworkProvider()
        networkProvider.response = HTTPURLResponse(url: URL(string: "https://example.com/sdk.log")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        networkProvider.responseData = Data()

        return networkProvider
    }

    private func makeAssembly(baseURL: String?) -> (ServicesAssembly, MockNetworkProvider) {
        let internalConfig = InternalConfig(userId: "user_abc")
        let miscAssembly = MiscAssembly(apiKey: "test-key", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)
        let servicesAssembly = ServicesAssembly(apiKey: "test-key", miscAssembly: miscAssembly, baseURL: baseURL)
        miscAssembly.servicesAssembly = servicesAssembly
        let networkProvider: MockNetworkProvider = makeNetworkProvider()
        servicesAssembly.networkProviderOverride = networkProvider

        return (servicesAssembly, networkProvider)
    }

    func testTheCrashTransportGoesThroughTheConfiguredProxy() async throws {
        let (servicesAssembly, networkProvider) = makeAssembly(baseURL: "https://proxy.example.com/")

        _ = await servicesAssembly.crashReportsTransport().send(body: ["exception": "boom"])

        let url: URL = try XCTUnwrap(networkProvider.sentRequests.first?.url)
        XCTAssertEqual(url.absoluteString, "https://proxy.example.com/sdk.log",
                       "a host that requires all traffic through its proxy must not see direct calls to sdk-logs.qonversion.io")
    }

    func testWithoutAProxyTheCrashTransportKeepsItsOwnHost() async throws {
        let (servicesAssembly, networkProvider) = makeAssembly(baseURL: nil)

        _ = await servicesAssembly.crashReportsTransport().send(body: ["exception": "boom"])

        let url: URL = try XCTUnwrap(networkProvider.sentRequests.first?.url)
        XCTAssertEqual(url.absoluteString, "https://sdk-logs.qonversion.io/sdk.log",
                       "the default target is a different host from the API and must stay that way")
    }
}
