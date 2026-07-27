//
//  AdvertisingIdReaderTests.swift
//  QonversionUnitTests
//
//  The reader resolves the system advertising identifier through the
//  Objective-C runtime, by names it assembles at run time. The fakes below are
//  deliberately registered under harmless names, never under the production
//  one: the production lookup must keep returning nil in this test host, which
//  is exactly the behaviour a Kids Category app gets.
//

import XCTest
@testable import Qonversion

@objc(QonversionTestIdentifierProvider)
private final class FakeIdentifierProvider: NSObject {

    static let identifier = UUID()

    private static let sharedInstance = FakeIdentifierProvider()

    @objc static func testSharedInstance() -> AnyObject {
        return sharedInstance
    }

    @objc func testIdentifier() -> NSUUID {
        return FakeIdentifierProvider.identifier as NSUUID
    }
}

@objc(QonversionTestSilentProvider)
private final class FakeSilentProvider: NSObject {}

@objc(QonversionTestMisshapenProvider)
private final class FakeMisshapenProvider: NSObject {

    private static let sharedInstance = FakeMisshapenProvider()

    @objc static func testSharedInstance() -> AnyObject {
        return sharedInstance
    }

    @objc func testIdentifier() -> String {
        return "not a uuid at all"
    }
}

final class AdvertisingIdReaderTests: XCTestCase {

    private let providerClassName = "QonversionTestIdentifierProvider"
    private let instanceAccessorName = "testSharedInstance"
    private let identifierAccessorName = "testIdentifier"

    // MARK: - Obfuscation transform

    func testDecodingTheStoredClassNameYieldsTheRuntimeName() {
        let decoded: String = AdvertisingIdReader.decoded(AdvertisingIdReader.ObfuscatedNames.identifierProviderClass)

        XCTAssertEqual(decoded, "ASIdentifierManager")
    }

    func testDecodingTheStoredInstanceAccessorYieldsTheRuntimeName() {
        let decoded: String = AdvertisingIdReader.decoded(AdvertisingIdReader.ObfuscatedNames.instanceAccessor)

        XCTAssertEqual(decoded, "sharedManager")
    }

    func testDecodingTheStoredIdentifierAccessorYieldsTheRuntimeName() {
        let decoded: String = AdvertisingIdReader.decoded(AdvertisingIdReader.ObfuscatedNames.identifierAccessor)

        XCTAssertEqual(decoded, "advertisingIdentifier")
    }

    func testTheTransformIsItsOwnInverse() {
        let names: [[UInt8]] = [
            AdvertisingIdReader.ObfuscatedNames.identifierProviderClass,
            AdvertisingIdReader.ObfuscatedNames.instanceAccessor,
            AdvertisingIdReader.ObfuscatedNames.identifierAccessor,
        ]

        for encoded in names {
            let decoded: String = AdvertisingIdReader.decoded(encoded)
            let reEncoded: String = AdvertisingIdReader.decoded(Array(decoded.utf8))

            XCTAssertEqual(reEncoded, String(decoding: encoded, as: UTF8.self))
        }
    }

    func testTheStoredNamesAreNotReadableWithoutDecoding() {
        // The bytes as compiled must not spell the production names out — not
        // even as a substring, which is all a binary scanner needs.
        let stored: [String] = [
            String(decoding: AdvertisingIdReader.ObfuscatedNames.identifierProviderClass, as: UTF8.self),
            String(decoding: AdvertisingIdReader.ObfuscatedNames.instanceAccessor, as: UTF8.self),
            String(decoding: AdvertisingIdReader.ObfuscatedNames.identifierAccessor, as: UTF8.self),
        ]

        for forbidden in ["AdSupport", "ASIdentifierManager", "sharedManager", "advertisingIdentifier"] {
            let isReadable: Bool = stored.contains { $0.contains(forbidden) }

            XCTAssertFalse(isReadable, "The stored bytes spell out \"\(forbidden)\"")
        }
    }

    /// The one path no CI host can exercise: on a machine without the
    /// framework, swapping two of these names changes nothing observable, and
    /// the identifier would just quietly stop being read on device.
    func testTheProductionLookupIsWiredToTheRightNameInEachPosition() {
        let names: (className: String, instanceAccessorName: String, identifierAccessorName: String) = AdvertisingIdReader.runtimeNames()

        XCTAssertEqual(names.className, "ASIdentifierManager")
        XCTAssertEqual(names.instanceAccessorName, "sharedManager")
        XCTAssertEqual(names.identifierAccessorName, "advertisingIdentifier")
    }

    // MARK: - The production lookup in a host that does not link the framework

    func testAdvertisingIdIsNilWhenTheHostDoesNotLinkTheAdvertisingFramework() {
        // Nothing registers the production class in this test host, so the
        // lookup finds nothing — the Kids Category path.
        let reader = AdvertisingIdReader()

        XCTAssertNil(reader.advertisingId())
    }

    func testTheRuntimeLookupIsNilWhenTheClassIsUnresolvable() {
        let identifier: String? = AdvertisingIdReader.runtimeIdentifier(
            className: "QonversionTestClassThatDoesNotExist",
            instanceAccessorName: instanceAccessorName,
            identifierAccessorName: identifierAccessorName
        )

        XCTAssertNil(identifier)
    }

    // MARK: - The runtime lookup against a resolvable provider

    func testTheRuntimeLookupReadsTheIdentifierThroughTheObjectiveCRuntime() {
        let identifier: String? = AdvertisingIdReader.runtimeIdentifier(
            className: providerClassName,
            instanceAccessorName: instanceAccessorName,
            identifierAccessorName: identifierAccessorName
        )

        XCTAssertEqual(identifier, FakeIdentifierProvider.identifier.uuidString)
    }

    func testTheRuntimeLookupIsNilWhenTheClassDoesNotAnswerTheInstanceAccessor() {
        let identifier: String? = AdvertisingIdReader.runtimeIdentifier(
            className: "QonversionTestSilentProvider",
            instanceAccessorName: instanceAccessorName,
            identifierAccessorName: identifierAccessorName
        )

        XCTAssertNil(identifier)
    }

    func testTheRuntimeLookupIsNilWhenTheInstanceDoesNotAnswerTheIdentifierAccessor() {
        let identifier: String? = AdvertisingIdReader.runtimeIdentifier(
            className: providerClassName,
            instanceAccessorName: instanceAccessorName,
            identifierAccessorName: "testAccessorThatDoesNotExist"
        )

        XCTAssertNil(identifier)
    }

    func testTheRuntimeLookupIsNilWhenTheAnswerIsNotAUuid() {
        let identifier: String? = AdvertisingIdReader.runtimeIdentifier(
            className: "QonversionTestMisshapenProvider",
            instanceAccessorName: instanceAccessorName,
            identifierAccessorName: identifierAccessorName
        )

        XCTAssertNil(identifier)
    }

    // MARK: - The all-zeroes identifier, pinned through the injected seam

    func testAdvertisingIdIsNilForTheAllZeroesIdentifier() {
        let rawIdentifierReader: AdvertisingIdReader.RawIdentifierReader = { "00000000-0000-0000-0000-000000000000" }
        let reader = AdvertisingIdReader(rawIdentifierReader: rawIdentifierReader)

        XCTAssertNil(reader.advertisingId())
    }

    func testAdvertisingIdIsReturnedWhenTheIdentifierIsGranted() {
        let grantedIdentifier = "8264F4B7-3A0C-4D18-9A2E-5C1A9D0B7E33"
        let rawIdentifierReader: AdvertisingIdReader.RawIdentifierReader = { grantedIdentifier }
        let reader = AdvertisingIdReader(rawIdentifierReader: rawIdentifierReader)

        XCTAssertEqual(reader.advertisingId(), grantedIdentifier)
    }

    func testAdvertisingIdIsNilWhenTheRawReaderYieldsNothing() {
        let rawIdentifierReader: AdvertisingIdReader.RawIdentifierReader = { nil }
        let reader = AdvertisingIdReader(rawIdentifierReader: rawIdentifierReader)

        XCTAssertNil(reader.advertisingId())
    }

    // MARK: - The collector keeps its wire behaviour

    func testDeviceInfoCollectorReportsNoAdvertisingIdWithoutTheFramework() {
        let collector = DeviceInfoCollector()

        XCTAssertNil(collector.advertisingId())
        XCTAssertNil(collector.deviceInfo().advertisingId)
    }
}
