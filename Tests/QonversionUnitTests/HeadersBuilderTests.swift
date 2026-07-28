//
//  HeadersBuilderTests.swift
//  QonversionUnitTests
//
//  The request headers: cheap device slice, no empty values, and the
//  source override heuristic that survives upgrades from the ObjC SDK.
//

import XCTest
@testable import Qonversion

final class HeadersBuilderTests: XCTestCase {

    private var deviceInfoCollector: MockDeviceInfoCollector!
    private var userDefaults: UserDefaults!
    private var builder: HeadersBuilder!

    override func setUp() {
        super.setUp()
        deviceInfoCollector = MockDeviceInfoCollector()
        userDefaults = TestDefaults.makeIsolated()
        builder = HeadersBuilder(apiKey: "test-key", sdkVersion: "7.0.0", deviceInfoCollector: deviceInfoCollector, userDefaults: userDefaults)
    }

    override func tearDown() {
        builder = nil
        userDefaults = nil
        deviceInfoCollector = nil
        super.tearDown()
    }

    private func builtRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api2.qonversion.io/v4/products")!)
        builder.addHeaders(to: &request)
        return request
    }

    func testHeadersUseTheCheapDeviceSliceOnly() {
        _ = builtRequest()

        XCTAssertEqual(deviceInfoCollector.headerDeviceInfoCallsCount, 1)
        XCTAssertEqual(deviceInfoCollector.deviceInfoCallsCount, 0, "the full device snapshot (IDFA/IDFV/model) must not be built per request")
    }

    func testDefaultSourceIsNativeSdk() {
        let request = builtRequest()

        XCTAssertEqual(request.value(forHTTPHeaderField: "Source"), "iOS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Source-Version"), "7.0.0")
    }

    func testWrapperOverridesBothSourceHeaders() {
        userDefaults.set("flutter", forKey: "com.qonversion.keys.source")
        userDefaults.set("9.9.9", forKey: "com.qonversion.keys.sourceVersion")

        let request = builtRequest()

        XCTAssertEqual(request.value(forHTTPHeaderField: "Source"), "flutter")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Source-Version"), "9.9.9")
    }

    func testObjcLeftoverVersionWithoutSourceIsIgnored() {
        // The production ObjC SDK persisted its own version into this key;
        // after an upgrade it must not shadow the Swift SDK version forever.
        userDefaults.set("6.13.1", forKey: "com.qonversion.keys.sourceVersion")

        let request = builtRequest()

        XCTAssertEqual(request.value(forHTTPHeaderField: "Source"), "iOS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Source-Version"), "7.0.0")
    }

    func testEmptyDeviceValuesAreOmittedNotSentAsEmptyStrings() {
        deviceInfoCollector.device = Device(
            osName: "tvOS", osVersion: "17.0", model: nil,
            appVersion: nil, country: nil, language: nil,
            advertisingId: nil, vendorId: nil, installDate: 0
        )

        let request = builtRequest()

        XCTAssertNil(request.value(forHTTPHeaderField: "app-version"))
        XCTAssertNil(request.value(forHTTPHeaderField: "country"))
        XCTAssertNil(request.value(forHTTPHeaderField: "User-locale"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Platform"), "tvOS")
    }
}
