//
//  EntitlementsCacheLifetimeTests.swift
//  QonversionUnitTests
//
//  The lifetime bounds how long cached entitlements participate in the local
//  fallback. Values match the production SDK day counts (TDD — written before
//  the implementation).
//

import XCTest
@testable import Qonversion

final class EntitlementsCacheLifetimeTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60

    func testSecondsMatchProductionDayCounts() {
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.week.seconds, 7 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.twoWeeks.seconds, 14 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.month.seconds, 30 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.twoMonths.seconds, 60 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.threeMonths.seconds, 90 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.sixMonths.seconds, 180 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.year.seconds, 365 * day)
        XCTAssertEqual(Qonversion.EntitlementsCacheLifetime.unlimited.seconds, .greatestFiniteMagnitude)
    }

    func testConfigurationDefaultsToMonth() {
        let configuration = Qonversion.Configuration(apiKey: "key", launchMode: .analytics)

        XCTAssertEqual(configuration.entitlementsCacheLifetime, .month)
    }

    func testConfigurationStoresCustomLifetime() {
        let configuration = Qonversion.Configuration(apiKey: "key", launchMode: .analytics, entitlementsCacheLifetime: .year)

        XCTAssertEqual(configuration.entitlementsCacheLifetime, .year)
    }
}
