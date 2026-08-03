//
//  ConfigurationTests.swift
//  QonversionUnitTests
//
//  proxyURL redirects all SDK requests to the given server. Normalization
//  matches the production SDK: https scheme is prepended when missing, a
//  trailing slash is appended (TDD — written before the implementation).
//

import XCTest
@_spi(QonversionInternal) @testable import Qonversion

final class ConfigurationTests: XCTestCase {

    func testConfigurationKeepsTheCustomDefaultsInstance() {
        let defaults = TestDefaults.makeIsolated()
        let configuration = Qonversion.Configuration(
            apiKey: "key",
            launchMode: .analytics,
            userDefaults: defaults
        )

        XCTAssertTrue(configuration.userDefaults === defaults)
    }

    // A fixed suite name maps to one file in a non-sandboxed macOS process's own
    // preferences folder — shared by every Qonversion app the user has installed.
    func testSuiteNameIsScopedToTheHostBundleIdentifier() {
        let expectedBundleComponent = Bundle.main.bundleIdentifier ?? "default"

        XCTAssertTrue(QonversionDefaults.suiteName.hasPrefix("io.qonversion.sdk."))
        XCTAssertTrue(QonversionDefaults.suiteName.hasSuffix(expectedBundleComponent))
        XCTAssertNotEqual(QonversionDefaults.suiteName, "io.qonversion.sdk", "the bare suite name is shared by every app on a non-sandboxed Mac")
    }

    func testAssemblyWithoutCustomDefaultsUsesTheSdkSuite() {
        let suiteName = QonversionDefaults.suiteName
        let sdkDefaults = UserDefaults(suiteName: suiteName)!
        sdkDefaults.removePersistentDomain(forName: suiteName)
        defer { sdkDefaults.removePersistentDomain(forName: suiteName) }

        let assembly = QonversionAssembly(apiKey: "key", userDefaults: nil)
        assembly.servicesAssembly.miscAssembly.userDefaults.set("value", forKey: "test.internal-suite")

        XCTAssertEqual(sdkDefaults.string(forKey: "test.internal-suite"), "value")
    }

    func testAssemblyMovesSdkOwnedStandardValuesIntoTheInternalSuite() {
        let suiteName = QonversionDefaults.suiteName
        let sdkDefaults = UserDefaults(suiteName: suiteName)!
        let fallbackKey = "io.qonversion.sdk.storage.fallbackVendorId"
        let unrelatedKey = "test.host-setting"
        sdkDefaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        UserDefaults.standard.removeObject(forKey: unrelatedKey)
        defer {
            sdkDefaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            UserDefaults.standard.removeObject(forKey: unrelatedKey)
        }
        UserDefaults.standard.set("existing-fallback", forKey: fallbackKey)
        UserDefaults.standard.set("host-value", forKey: unrelatedKey)

        _ = QonversionAssembly(apiKey: "key", userDefaults: nil)

        XCTAssertEqual(sdkDefaults.string(forKey: fallbackKey), "existing-fallback")
        XCTAssertNil(UserDefaults.standard.object(forKey: fallbackKey))
        XCTAssertEqual(UserDefaults.standard.string(forKey: unrelatedKey), "host-value")
        XCTAssertNil(sdkDefaults.object(forKey: unrelatedKey))
    }

    func testAssemblyDoesNotMigrateStandardValuesIntoCustomDefaults() {
        let customDefaults = TestDefaults.makeIsolated()
        let fallbackKey = "io.qonversion.sdk.storage.fallbackVendorId"
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        defer { UserDefaults.standard.removeObject(forKey: fallbackKey) }
        UserDefaults.standard.set("standard-fallback", forKey: fallbackKey)

        _ = QonversionAssembly(apiKey: "key", userDefaults: customDefaults)

        XCTAssertNil(customDefaults.object(forKey: fallbackKey))
        XCTAssertEqual(UserDefaults.standard.string(forKey: fallbackKey), "standard-fallback")
    }

    func testDefaultConfigurationHasNoCustomBaseURL() {
        let configuration = Qonversion.Configuration(apiKey: "key", launchMode: .analytics)

        XCTAssertNil(configuration.baseURL)
    }

    func testProxyURLWithoutSchemeGetsHttpsAndTrailingSlash() {
        let configuration = Qonversion.Configuration(apiKey: "key", launchMode: .analytics, proxyURL: "proxy.example.com")

        XCTAssertEqual(configuration.baseURL, "https://proxy.example.com/")
    }

    func testProxyURLWithHttpSchemeIsKept() {
        let configuration = Qonversion.Configuration(apiKey: "key", launchMode: .analytics, proxyURL: "http://proxy.example.com")

        XCTAssertEqual(configuration.baseURL, "http://proxy.example.com/")
    }

    func testProxyURLWithSchemeAndTrailingSlashIsUnchanged() {
        let configuration = Qonversion.Configuration(apiKey: "key", launchMode: .analytics, proxyURL: "https://proxy.example.com/")

        XCTAssertEqual(configuration.baseURL, "https://proxy.example.com/")
    }

    // MARK: - plumbing to the request processor

    func testServicesAssemblyUsesCustomBaseURL() {
        let miscAssembly = MiscAssembly(apiKey: "key", userDefaults: TestDefaults.makeIsolated(), internalConfig: InternalConfig(userId: ""))
        let servicesAssembly = ServicesAssembly(apiKey: "key", miscAssembly: miscAssembly, baseURL: "https://proxy.example.com/")
        miscAssembly.servicesAssembly = servicesAssembly

        let processor = servicesAssembly.requestProcessor() as? RequestProcessor

        XCTAssertEqual(processor?.baseURL, "https://proxy.example.com/")
    }

    func testServicesAssemblyDefaultsToProductionBaseURL() {
        let miscAssembly = MiscAssembly(apiKey: "key", userDefaults: TestDefaults.makeIsolated(), internalConfig: InternalConfig(userId: ""))
        let servicesAssembly = ServicesAssembly(apiKey: "key", miscAssembly: miscAssembly)
        miscAssembly.servicesAssembly = servicesAssembly

        let processor = servicesAssembly.requestProcessor() as? RequestProcessor

        XCTAssertEqual(processor?.baseURL, "https://api2.qonversion.io/")
    }
}
