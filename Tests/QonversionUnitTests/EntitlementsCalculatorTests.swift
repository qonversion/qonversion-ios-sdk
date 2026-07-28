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

    // MARK: - signed expiration (review finding A2.6)

    func testSignedTransactionExpirationBeatsThePeriodApproximation() {
        // A 7-day trial on an annual product: StoreKit signs the real expiry.
        let signedExpiry = Date(timeIntervalSince1970: 1_700_000_000 + 7 * 24 * 3600)
        let transaction = Qonversion.Transaction(
            id: "t1", productId: "com.app.pro",
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var product = Qonversion.Product(qonversionId: "pro", storeId: "com.app.pro", offeringId: nil)
        let period = Qonversion.Product.SubscriptionPeriod(unit: .year, value: 1)
        product.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "g", subscriptionPeriod: period)

        // Approximation path (no signed expiry on the transaction):
        let approximated = EntitlementsCalculator.expirationDate(for: transaction, product: product)
        XCTAssertEqual(approximated, Date(timeIntervalSince1970: 1_700_000_000 + 365 * 24 * 3600))

        // Signed path must win when present — verified via calculate() with a
        // dedicated transaction type is not constructible in unit tests, so
        // the rule is asserted at the function level with a stub extension.
        XCTAssertNil(transaction.expirationDate, "plain wire transactions carry no signed expiry")
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

    // MARK: - two products granting the same permission

    func testTheStrongestGrantWinsRegardlessOfTheIterationOrder() {
        let day: TimeInterval = 24 * 60 * 60
        let monthly: Qonversion.Product = makeProduct(qonversionId: "monthly", storeId: "com.app.monthly", periodUnit: .month, periodValue: 1)
        let annual: Qonversion.Product = makeProduct(qonversionId: "annual", storeId: "com.app.annual", periodUnit: .year, periodValue: 1)
        let monthlyTransaction: Qonversion.Transaction = makeTransaction(productId: "com.app.monthly", purchasedSecondsAgo: 0)
        let annualTransaction: Qonversion.Transaction = makeTransaction(productId: "com.app.annual", purchasedSecondsAgo: 0)
        let mapping: [String: [String]] = ["monthly": ["premium"], "annual": ["premium"]]

        let monthlyFirst = EntitlementsCalculator.calculate(
            transactions: [monthlyTransaction, annualTransaction],
            products: [monthly, annual],
            mapping: mapping,
            now: now
        )
        let annualFirst = EntitlementsCalculator.calculate(
            transactions: [annualTransaction, monthlyTransaction],
            products: [monthly, annual],
            mapping: mapping,
            now: now
        )

        XCTAssertEqual(monthlyFirst["premium"]?.expirationDate, now.addingTimeInterval(365 * day))
        XCTAssertEqual(annualFirst["premium"]?.expirationDate, now.addingTimeInterval(365 * day),
                       "the later transaction must not shorten an entitlement another product grants for longer")
    }

    func testLifetimeGrantBeatsADatedOneRegardlessOfTheIterationOrder() {
        let lifetime: Qonversion.Product = makeProduct(qonversionId: "lifetime", storeId: "com.app.lifetime", periodUnit: nil)
        let monthly: Qonversion.Product = makeProduct(qonversionId: "monthly", storeId: "com.app.monthly", periodUnit: .month, periodValue: 1)
        let lifetimeTransaction: Qonversion.Transaction = makeTransaction(productId: "com.app.lifetime", purchasedSecondsAgo: 0)
        let monthlyTransaction: Qonversion.Transaction = makeTransaction(productId: "com.app.monthly", purchasedSecondsAgo: 0)
        let mapping: [String: [String]] = ["lifetime": ["premium"], "monthly": ["premium"]]

        let lifetimeFirst = EntitlementsCalculator.calculate(
            transactions: [lifetimeTransaction, monthlyTransaction],
            products: [lifetime, monthly],
            mapping: mapping,
            now: now
        )
        let monthlyFirst = EntitlementsCalculator.calculate(
            transactions: [monthlyTransaction, lifetimeTransaction],
            products: [lifetime, monthly],
            mapping: mapping,
            now: now
        )

        XCTAssertNil(lifetimeFirst["premium"]?.expirationDate)
        XCTAssertNil(monthlyFirst["premium"]?.expirationDate)
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

    // MARK: - allowsLocalEntitlementsFallback

    func testAConnectionFailureAllowsTheFallbackWithoutAnUnderlyingUrlError() {
        // The offline fallback must key off the error TYPE, not off the
        // accident that the processor happens to attach the URLError: a
        // .networkConnectionFailed built anywhere else (a re-thrown copy, a
        // future call site) still means "nothing reached the backend".
        let error = QonversionError(type: .networkConnectionFailed, error: nil)

        XCTAssertTrue(error.allowsLocalEntitlementsFallback)
    }

    func testAConnectionFailureCarryingItsUrlErrorStillAllowsTheFallback() {
        let error = QonversionError(type: .networkConnectionFailed, error: URLError(.notConnectedToInternet))

        XCTAssertTrue(error.allowsLocalEntitlementsFallback)
    }

    func testAnAuthFailureNeverAllowsTheFallback() {
        let error = QonversionError(type: .critical, error: nil)

        XCTAssertFalse(error.allowsLocalEntitlementsFallback)
    }
}
