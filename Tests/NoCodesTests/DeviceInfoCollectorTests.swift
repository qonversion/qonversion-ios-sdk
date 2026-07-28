//
//  DeviceInfoCollectorTests.swift
//  NoCodesTests
//
//  The device record every request is stamped with: the platform name and the
//  value semantics of the record itself.
//

import XCTest
@testable import NoCodes

@MainActor
final class DeviceInfoCollectorTests: XCTestCase {

    /// The same values the main SDK reports: the backend sees one platform
    /// vocabulary, whichever module sent the request. "tvos" in lower case and
    /// visionOS reporting as iOS were both divergences from it.
    func testThePlatformIsTheOneThisBuildRunsOn() {
        let collector = DeviceInfoCollector()

        let osName: String = collector.deviceInfo().osName

        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(osName, "macCatalyst")
        #elseif os(macOS)
        XCTAssertEqual(osName, "macOS")
        #elseif os(tvOS)
        XCTAssertEqual(osName, "tvOS")
        #elseif os(watchOS)
        XCTAssertEqual(osName, "watchOS")
        #elseif os(visionOS)
        XCTAssertEqual(osName, "visionOS")
        #else
        XCTAssertEqual(osName, "iOS")
        #endif
    }

    /// The vocabulary is closed, and every name in it is spelled the way the
    /// backend expects it.
    func testThePlatformIsOneOfTheNamesTheBackendKnows() {
        let knownNames: Set<String> = ["iOS", "macOS", "macCatalyst", "tvOS", "watchOS", "visionOS"]
        let collector = DeviceInfoCollector()

        XCTAssertTrue(knownNames.contains(collector.deviceInfo().osName))
    }
}

final class NoCodesDeviceTests: XCTestCase {

    func testTwoRecordsWithTheSameValuesAreEqual() {
        XCTAssertEqual(makeDevice(), makeDevice())
    }

    func testRecordsDifferingInASingleFieldAreNotEqual() {
        XCTAssertNotEqual(makeDevice(), makeDevice(osVersion: "18.0"))
        XCTAssertNotEqual(makeDevice(), makeDevice(vendorId: "vendor-2"))
    }

    private func makeDevice(osVersion: String = "17.4", vendorId: String? = "vendor-1") -> Device {
        return Device(
            manufacturer: "Apple",
            osName: "iOS",
            osVersion: osVersion,
            model: "iPhone15,2",
            appVersion: "1.2.3",
            country: "US",
            language: "en",
            timezone: "Europe/Berlin",
            vendorId: vendorId,
            installDate: 1700000000
        )
    }
}
