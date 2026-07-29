//
//  PrivacyManifestTests.swift
//  QonversionUnitTests
//
//  The privacy manifest is what App Review reads, and a Required Reason API
//  used without its category declared is a rejection of every app that embeds
//  the SDK. One file ships as a resource of BOTH targets, so the manifest
//  itself and both build systems' references to it are pinned here.
//

import XCTest
@testable import Qonversion

final class PrivacyManifestTests: XCTestCase {

    // MARK: - locating the manifest that actually ships

    /// The manifest as the build copies it into the product, falling back to
    /// the checked-in file so the test also runs under the Xcode project.
    private static func manifestURL() -> URL? {
        if let bundled: URL = bundledManifestURL() {
            return bundled
        }

        return sourceManifestURL()
    }

    private static func bundledManifestURL() -> URL? {
        let testBundleURL: URL = Bundle(for: PrivacyManifestTests.self).bundleURL
        let roots: [URL] = [testBundleURL, testBundleURL.deletingLastPathComponent()]

        for root in roots {
            guard let entries: [URL] = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }

            for entry in entries where entry.pathExtension == "bundle" {
                let candidate: URL = entry.appendingPathComponent("PrivacyInfo.xcprivacy")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func sourceManifestURL() -> URL? {
        let url: URL = repositoryRoot().appendingPathComponent("Sources/PrivacyInfo.xcprivacy")

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func manifest() throws -> [String: Any] {
        let url: URL = try XCTUnwrap(Self.manifestURL(), "no privacy manifest was found")
        let data = try Data(contentsOf: url)
        let plist: Any = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        return try XCTUnwrap(plist as? [String: Any], "the manifest is not a plist dictionary")
    }

    private func accessedAPITypes() throws -> [[String: Any]] {
        return try XCTUnwrap(manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    }

    private func reasons(forCategory category: String) throws -> [String] {
        let entry: [String: Any]? = try accessedAPITypes().first { $0["NSPrivacyAccessedAPIType"] as? String == category }
        let reasons: [String] = (entry?["NSPrivacyAccessedAPITypeReasons"] as? [String]) ?? []

        return reasons
    }

    private func collectedDataTypes() throws -> [[String: Any]] {
        return try XCTUnwrap(manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    }

    private func collectedEntry(_ type: String) throws -> [String: Any]? {
        return try collectedDataTypes().first { $0["NSPrivacyCollectedDataType"] as? String == type }
    }

    func testTheManifestShipsInsideTheBuiltProduct() {
        XCTAssertNotNil(Self.bundledManifestURL(), "the manifest is not among the built resources — nothing would reach App Review")
    }

    // MARK: - Required Reason APIs

    func testFileTimestampAccessIsDeclared() throws {
        // DeviceInfoCollector.installDate() reads FileAttributeKey.creationDate
        // through FileManager.attributesOfItem(atPath:) on every device
        // collection, and the NoCodes collector does the same. Undeclared, that
        // is an App Store rejection for the host app.
        let reasons: [String] = try reasons(forCategory: "NSPrivacyAccessedAPICategoryFileTimestamp")

        XCTAssertFalse(reasons.isEmpty, "the SDK reads file timestamps but declares no reason for it")
        XCTAssertTrue(reasons.contains("C617.1"), "the timestamps read are of files inside the app container, which is exactly C617.1")
    }

    func testUserDefaultsAccessKeepsItsExistingReason() throws {
        let reasons: [String] = try reasons(forCategory: "NSPrivacyAccessedAPICategoryUserDefaults")

        XCTAssertTrue(reasons.contains("CA92.1"))
    }

    func testEveryDeclaredReasonIsOneApplePermitsForItsCategory() throws {
        // A typo here is invisible until App Review rejects the host app.
        let permitted: [String: Set<String>] = [
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1", "8FFB.1", "3D61.1"],
            "NSPrivacyAccessedAPICategoryDiskSpace": ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
            "NSPrivacyAccessedAPICategoryActiveKeyboards": ["3EC4.1", "54BD.1"]
        ]

        for entry in try accessedAPITypes() {
            let category: String = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            let allowed: Set<String> = try XCTUnwrap(permitted[category], "unknown API category \(category)")
            let declared: [String] = try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])

            XCTAssertFalse(declared.isEmpty, "\(category) declares no reason at all")
            for reason in declared {
                XCTAssertTrue(allowed.contains(reason), "\(reason) is not a permitted reason for \(category)")
            }
        }
    }

    // MARK: - collected data types

    func testDeviceIdCollectionIsDeclared() throws {
        // Device.advertisingId / Device.vendorId ride the device record to
        // POST /v4/users/{uid}/device on every launch that changes it.
        let entry: [String: Any] = try XCTUnwrap(collectedEntry("NSPrivacyCollectedDataTypeDeviceID"),
                                                 "the SDK ships advertising_id and vendor_id but declares no Device ID collection")

        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true, "the device record is stored under the user's uid")
        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertFalse((entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []).isEmpty)
    }

    func testUserIdCollectionIsDeclared() throws {
        // The SDK's own uid rides every request, and identify(userId:) ships
        // the host's identifier as well.
        let entry: [String: Any] = try XCTUnwrap(collectedEntry("NSPrivacyCollectedDataTypeUserID"))

        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
    }

    func testCrashDataCollectionIsDeclared() throws {
        // CrashReportsTransport posts exception name, reason and stack trace
        // to the sdk-logs service on the launch after an SDK crash.
        let entry: [String: Any] = try XCTUnwrap(collectedEntry("NSPrivacyCollectedDataTypeCrashData"))

        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertTrue((entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []).contains("NSPrivacyCollectedDataTypePurposeAppFunctionality"))
    }

    func testPurchaseHistoryCollectionSurvives() throws {
        XCTAssertNotNil(try collectedEntry("NSPrivacyCollectedDataTypePurchaseHistory"))
    }

    func testTheManifestDoesNotClaimTracking() throws {
        XCTAssertEqual(try manifest()["NSPrivacyTracking"] as? Bool, false)
    }

    // MARK: - both build systems ship it

    func testBothPackageTargetsCopyTheManifest() throws {
        let package = try String(contentsOf: Self.repositoryRoot().appendingPathComponent("Package.swift"), encoding: .utf8)

        XCTAssertTrue(package.contains(#".copy("PrivacyInfo.xcprivacy")"#), "the Qonversion target must copy the manifest")
        XCTAssertTrue(package.contains(#".copy("../PrivacyInfo.xcprivacy")"#), "the NoCodes target must copy the same manifest")
    }

    func testBothXcodeTargetsCopyTheManifest() throws {
        let project = try String(contentsOf: Self.repositoryRoot().appendingPathComponent("Qonversion.xcodeproj/project.pbxproj"), encoding: .utf8)
        let references: Int = project.components(separatedBy: "PrivacyInfo.xcprivacy in Resources */,").count - 1

        XCTAssertEqual(references, 2, "the manifest must sit in the Resources phase of both the Qonversion and the NoCodes target")
    }
}
