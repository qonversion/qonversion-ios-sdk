//
//  EntitlementsCalculatorTests.swift
//  QonversionUnitTests
//
//  Locks the local entitlements calculation to the production SDK behavior:
//  day-based period approximation (month = 30, year = 365), lifetime grants
//  for products without a period, skipping expired transactions, permission
//  fan-out via the mapping, and the production merge rule.
//

import XCTest
@testable import Qonversion

final class EntitlementsCalculatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeProduct(qonversionId: String = "pro", storeId: String = "com.app.pro", periodUnit: Qonversion.Product.SubscriptionPeriod.Unit? = .month, periodValue: Int = 1) -> Qonversion.Product {
        var product = Qonversion.Product(qonversionId: qonversionId, storeId: storeId, offeringId: nil)
        if let periodUnit {
            product.subscription = Qonversion.Product.SubscriptionInfo(
                subscriptionGroupId: "group",
                subscriptionPeriod: Qonversion.Product.SubscriptionPeriod(unit: periodUnit, value: periodValue)
            )
        }
        return product
    }

    private func makeTransaction(productId: String = "com.app.pro", purchasedSecondsAgo: TimeInterval) -> Qonversion.Transaction {
        Qonversion.Transaction(id: UUID().uuidString, productId: productId, purchaseDate: now.addingTimeInterval(-purchasedSecondsAgo))
    }

    // MARK: - Period approximation (production-exact: 1/7/30/365)

    func testPeriodDaysUsesProductionApproximation() {
        XCTAssertEqual(EntitlementsCalculator.periodDays(.init(unit: .day, value: 1)), 1)
        XCTAssertEqual(EntitlementsCalculator.periodDays(.init(unit: .week, value: 2)), 14)
        XCTAssertEqual(EntitlementsCalculator.periodDays(.init(unit: .month, value: 1)), 30)
        XCTAssertEqual(EntitlementsCalculator.periodDays(.init(unit: .month, value: 3)), 90)
        XCTAssertEqual(EntitlementsCalculator.periodDays(.init(unit: .year, value: 1)), 365)
    }

    // MARK: - Grants

    func testActiveSubscriptionGrantsEntitlementPerMappedPermission() {
        let day: TimeInterval = 24 * 60 * 60
        let entitlements = EntitlementsCalculator.calculate(
            transactions: [makeTransaction(purchasedSecondsAgo: 10 * day)],
            products: [makeProduct()],                       // month = 30 days
            mapping: ["pro": ["premium", "extra"]],
            now: now
        )

        XCTAssertEqual(Set(entitlements.keys), ["premium", "extra"])
        let premium = entitlements["premium"]
        XCTAssertEqual(premium?.active, true)
        XCTAssertEqual(premium?.source, .appStore)
        XCTAssertEqual(premium?.productId, "pro")
        XCTAssertEqual(premium?.expirationDate, now.addingTimeInterval(20 * day))
    }

    func testExpiredTransactionIsSkippedEntirely() {
        let day: TimeInterval = 24 * 60 * 60
        let entitlements = EntitlementsCalculator.calculate(
            transactions: [makeTransaction(purchasedSecondsAgo: 31 * day)],   // month expired
            products: [makeProduct()],
            mapping: ["pro": ["premium"]],
            now: now
        )

        XCTAssertTrue(entitlements.isEmpty)
    }

    func testProductWithoutPeriodGrantsLifetimeEntitlement() {
        let entitlements = EntitlementsCalculator.calculate(
            transactions: [makeTransaction(purchasedSecondsAgo: 365 * 24 * 60 * 60)],
            products: [makeProduct(periodUnit: nil)],
            mapping: ["pro": ["premium"]],
            now: now
        )

        XCTAssertEqual(entitlements["premium"]?.active, true)
        XCTAssertNil(entitlements["premium"]?.expirationDate)
    }

    func testUnknownProductGrantsNothing() {
        // Production: no product match -> no relation lookup -> no grant.
        let entitlements = EntitlementsCalculator.calculate(
            transactions: [makeTransaction(productId: "com.app.unknown", purchasedSecondsAgo: 0)],
            products: [makeProduct()],
            mapping: ["pro": ["premium"]],
            now: now
        )

        XCTAssertTrue(entitlements.isEmpty)
    }

    func testProductWithoutMappingGrantsNothing() {
        let entitlements = EntitlementsCalculator.calculate(
            transactions: [makeTransaction(purchasedSecondsAgo: 0)],
            products: [makeProduct()],
            mapping: [:],
            now: now
        )

        XCTAssertTrue(entitlements.isEmpty)
    }

    // MARK: - Merge (production rule)

    private func entitlement(id: String, active: Bool, expiresIn: TimeInterval?) -> Qonversion.Entitlement {
        Qonversion.Entitlement(id: id, active: active, source: .appStore, expirationDate: expiresIn.map { now.addingTimeInterval($0) })
    }

    func testMergeAddsNewEntitlement() {
        let merged = EntitlementsCalculator.merge(
            ["premium": entitlement(id: "premium", active: true, expiresIn: 100)],
            into: [:]
        )
        XCTAssertEqual(merged["premium"]?.active, true)
    }

    func testMergeReplacesInactiveExisting() {
        let merged = EntitlementsCalculator.merge(
            ["premium": entitlement(id: "premium", active: true, expiresIn: 100)],
            into: ["premium": entitlement(id: "premium", active: false, expiresIn: 1_000_000)]
        )
        XCTAssertEqual(merged["premium"]?.active, true)
        XCTAssertEqual(merged["premium"]?.expirationDate, now.addingTimeInterval(100))
    }

    func testMergeKeepsActiveExistingThatExpiresLater() {
        let merged = EntitlementsCalculator.merge(
            ["premium": entitlement(id: "premium", active: true, expiresIn: 100)],
            into: ["premium": entitlement(id: "premium", active: true, expiresIn: 1000)]
        )
        XCTAssertEqual(merged["premium"]?.expirationDate, now.addingTimeInterval(1000))
    }

    func testMergeReplacesWhenCalculatedExpiresLater() {
        let merged = EntitlementsCalculator.merge(
            ["premium": entitlement(id: "premium", active: true, expiresIn: 1000)],
            into: ["premium": entitlement(id: "premium", active: true, expiresIn: 100)]
        )
        XCTAssertEqual(merged["premium"]?.expirationDate, now.addingTimeInterval(1000))
    }

    func testMergeLifetimeCalculatedWins() {
        let merged = EntitlementsCalculator.merge(
            ["premium": entitlement(id: "premium", active: true, expiresIn: nil)],
            into: ["premium": entitlement(id: "premium", active: true, expiresIn: 1000)]
        )
        XCTAssertNil(merged["premium"]?.expirationDate)
    }

    // MARK: - Restore dedup (latest transaction per product)

    func testLatestTransactionPerProductWins() {
        let older = makeTransaction(purchasedSecondsAgo: 100)
        let newer = makeTransaction(purchasedSecondsAgo: 10)

        let deduped = EntitlementsCalculator.latestTransactionsPerProduct([older, newer])

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, newer.id)
    }
}
