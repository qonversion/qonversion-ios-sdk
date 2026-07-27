//
//  IntegrationsInfoCollectorTests.swift
//  QonversionUnitTests
//
//  The collector resolves third-party SDK ids through the Objective-C runtime
//  by class name. The fake @objc classes below register under the production
//  class names, so the reflection path is exercised end to end.
//

import XCTest
@testable import Qonversion

@objc(Adjust)
private final class FakeAdjust: NSObject {
    @objc static func adid() -> String { "adjust-from-runtime" }
}

@objc(AppsFlyerLib)
private final class FakeAppsFlyerLib: NSObject {
    @objc static func shared() -> AnyObject { sharedInstance }
    private static let sharedInstance = FakeAppsFlyerLib()
    @objc func getAppsFlyerUID() -> String { "af-from-runtime" }
}

@objc(FBSDKAppEvents)
private final class FakeFBSDKAppEvents: NSObject {
    @objc static func anonymousID() -> String { "fb-from-runtime" }
}

final class IntegrationsInfoCollectorTests: XCTestCase {

    private var deviceInfoCollector: MockDeviceInfoCollector!
    private var collector: IntegrationsInfoCollector!

    override func setUp() {
        super.setUp()
        deviceInfoCollector = MockDeviceInfoCollector()
        collector = IntegrationsInfoCollector(deviceInfoCollector: deviceInfoCollector)
    }

    override func tearDown() {
        collector = nil
        deviceInfoCollector = nil
        super.tearDown()
    }

    func testAdjustIdIsResolvedThroughTheRuntime() {
        let expectation = expectation(description: "adjust id resolved")
        nonisolated(unsafe) var resolved: String?

        collector.adjustUserId { adid in
            resolved = adid
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(resolved, "adjust-from-runtime")
    }

    func testAppsFlyerUidIsResolvedThroughTheRuntime() {
        XCTAssertEqual(collector.appsFlyerUserId(), "af-from-runtime")
    }

    // The rule, in one line: the anonymous id is collected exactly when no
    // usable IDFA exists — tracking denied, or the host app not linking the
    // advertising identifier framework at all.

    func testFacebookAnonymousIdIsResolvedWithoutAUsableIdfa() {
        deviceInfoCollector.advertisingIdValue = nil

        XCTAssertEqual(collector.facebookAnonymousId(), "fb-from-runtime")
    }

    func testFacebookAnonymousIdIsSkippedWithARealIdfa() {
        // With a live IDFA Facebook attributes by it — the anonymous id must
        // not be collected even though the SDK is present.
        deviceInfoCollector.advertisingIdValue = "6D92078A-8246-4BA4-AE85-1BC6C137E623"

        XCTAssertNil(collector.facebookAnonymousId())
    }

    func testFacebookAnonymousIdDefersToTheCollectorOnWhatCountsAsAUsableIdfa() {
        // The zeroed identifier cannot reach here in production: the device
        // info collector already reports it as nil, which AdvertisingIdReaderTests
        // pins. So this collector does not second-guess it — a non-nil answer
        // is a real identifier by definition. Re-adding a zeroed-value check
        // here would duplicate the rule in a second place and fail this test.
        deviceInfoCollector.advertisingIdValue = "00000000-0000-0000-0000-000000000000"

        XCTAssertNil(collector.facebookAnonymousId())
    }
}
