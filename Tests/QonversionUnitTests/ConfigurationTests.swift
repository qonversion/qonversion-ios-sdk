//
//  ConfigurationTests.swift
//  QonversionUnitTests
//
//  proxyURL redirects all SDK requests to the given server. Normalization
//  matches the production SDK: https scheme is prepended when missing, a
//  trailing slash is appended (TDD — written before the implementation).
//

import XCTest
@testable import Qonversion

final class ConfigurationTests: XCTestCase {

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

        XCTAssertEqual(processor?.baseURL, "https://api.qonversion.io/")
    }
}
