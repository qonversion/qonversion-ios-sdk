//
//  ApiKeyChangeCleanerTests.swift
//  QonversionUnitTests
//
//  A project (apiKey) change is otherwise undetectable: almost every cache
//  key is unscoped, so the previous project's entitlements would be served to
//  the new one and the device row would never be created.
//

import XCTest
@testable import Qonversion

final class ApiKeyChangeCleanerTests: XCTestCase {

    private let entitlementsKey = "qonversion.keys.entitlements"
    private let userIdKey = "qonversion.keys.userId"
    private let originalUserIdKey = "qonversion.keys.originalUserId"
    private let userKey = "qonversion.keys.user"
    private let deviceKey = "io.qonversion.sdk.storage.device"
    private let storedApiKeyKey = "qonversion.keys.apiKey"

    private var defaults: UserDefaults!
    private var storage: LocalStorage!

    override func setUp() {
        super.setUp()
        defaults = TestDefaults.makeIsolated()
        storage = makeStorage(over: defaults)
    }

    override func tearDown() {
        storage = nil
        defaults = nil
        super.tearDown()
    }

    private func makeStorage(over userDefaults: UserDefaults) -> LocalStorage {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant

        return LocalStorage(userDefaults: userDefaults, encoder: encoder, decoder: decoder)
    }

    private func makeCleaner() -> ApiKeyChangeCleaner {
        let logger = LoggerWrapper()

        return ApiKeyChangeCleaner(localStorage: storage, logger: logger)
    }

    private func seedProjectData(apiKey: String) throws {
        try storage.set(["premium": Qonversion.Entitlement(id: "premium", active: true, source: .appStore)], forKey: entitlementsKey)
        storage.set(double: 100, forKey: "qonversion.keys.entitlementsTimestamp")
        storage.set(double: 100, forKey: "qonversion.keys.entitlementsBackendTimestamp")
        try storage.set(["pro": ["premium"]], forKey: "qonversion.keys.productsPermissions")
        try storage.set(["id": "QON_old"], forKey: userKey)
        storage.set(string: "external_1", forKey: "qonversion.keys.identityExternalId")
        storage.set(string: "QON_old", forKey: userIdKey)
        storage.set(string: "QON_original", forKey: originalUserIdKey)
        try storage.set(["com.app.pro": ["contextKeys": ["paywall"]]], forKey: "qonversion.keys.purchaseAssociations")
        try storage.set(["tx_1"], forKey: "qonversion.keys.surfacedTransactions")
        storage.set(bool: true, forKey: "qonversion.keys.historicalDataSynced")
        try storage.set(["report"], forKey: "qonversion.keys.crashReports")
        try storage.set(["id": "device_1"], forKey: deviceKey)
        try storage.set(["catalog"], forKey: "qonversion.keys.products." + apiKey)
        try storage.set(["queued"], forKey: "io.qonversion.sdk.storage.requests." + apiKey)
    }

    private func storedSdkKeys() -> [String] {
        let allKeys: [String] = Array(defaults.dictionaryRepresentation().keys)

        return allKeys.filter { $0.hasPrefix("qonversion.keys.") || $0.hasPrefix("io.qonversion.sdk.storage.") }.sorted()
    }

    // MARK: - Nothing to clean

    func testTheFirstRunStoresTheKeyAndWipesNothing() throws {
        try seedProjectData(apiKey: "key-a")

        let wiped: Bool = makeCleaner().run(apiKey: "key-a")

        XCTAssertFalse(wiped)
        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_old", "a fresh install has no stored key — an upgrade must keep its data")
        XCTAssertEqual(storage.string(forKey: storedApiKeyKey), "key-a")
    }

    func testTheSameKeyAcrossLaunchesWipesNothing() throws {
        _ = makeCleaner().run(apiKey: "key-a")
        try seedProjectData(apiKey: "key-a")

        let wiped: Bool = makeCleaner().run(apiKey: "key-a")

        XCTAssertFalse(wiped)
        XCTAssertNotNil(try storage.object(forKey: entitlementsKey, dataType: [String: Qonversion.Entitlement].self))
        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_old")
        XCTAssertNotNil(storage.data(forKey: deviceKey))
    }

    // MARK: - A changed key

    func testAChangedKeyDropsEverySdkOwnedKey() throws {
        _ = makeCleaner().run(apiKey: "key-a")
        try seedProjectData(apiKey: "key-a")

        let wiped: Bool = makeCleaner().run(apiKey: "key-b")

        XCTAssertTrue(wiped)
        XCTAssertEqual(storedSdkKeys(), [storedApiKeyKey], "only the new project key may survive a project switch")
    }

    func testAChangedKeyDropsThePreviousProjectsScopedCaches() throws {
        _ = makeCleaner().run(apiKey: "key-a")
        try seedProjectData(apiKey: "key-a")

        _ = makeCleaner().run(apiKey: "key-b")

        XCTAssertNil(storage.data(forKey: "qonversion.keys.products.key-a"))
        XCTAssertNil(storage.data(forKey: "io.qonversion.sdk.storage.requests.key-a"))
    }

    func testTheNewKeyIsStoredAfterTheWipe() throws {
        _ = makeCleaner().run(apiKey: "key-a")
        try seedProjectData(apiKey: "key-a")

        _ = makeCleaner().run(apiKey: "key-b")

        XCTAssertEqual(storage.string(forKey: storedApiKeyKey), "key-b", "without this the next launch would wipe again")
        XCTAssertFalse(makeCleaner().run(apiKey: "key-b"), "the switch is done — the next launch must not wipe")
    }

    func testTheHostsOwnValuesInTheSuiteAreLeftAlone() throws {
        // The configured suite may be the host's standard defaults: only the
        // enumerated SDK keys may be removed.
        _ = makeCleaner().run(apiKey: "key-a")
        defaults.set("host value", forKey: "com.app.host.setting")
        defaults.set(42, forKey: "someHostCounter")

        _ = makeCleaner().run(apiKey: "key-b")

        XCTAssertEqual(defaults.string(forKey: "com.app.host.setting"), "host value")
        XCTAssertEqual(defaults.integer(forKey: "someHostCounter"), 42)
    }
}

/// The wipe has to happen before anything reads or seeds storage, and it must
/// not fire on the very first run of an install upgrading from the previous
/// SDK generation.
final class ApiKeyChangeAssemblyOrderingTests: XCTestCase {

    private let legacySuiteName = "qonversion.localstorage.main"
    private let legacyUserIdKey = "com.qonversion.keys.storedUserID"
    private let legacyRelationKey = "com.qonversion.keys.products.permissions.relation"

    private var legacyDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
    }

    override func tearDown() {
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        legacyDefaults = nil
        super.tearDown()
    }

    private func makeStorage(over userDefaults: UserDefaults) -> LocalStorage {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant

        return LocalStorage(userDefaults: userDefaults, encoder: encoder, decoder: decoder)
    }

    func testAProjectSwitchStartsTheNextLaunchFromScratch() throws {
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        _ = QonversionAssembly(apiKey: "key-a", userDefaults: defaults)
        let storage: LocalStorage = makeStorage(over: defaults)
        let firstUserId: String? = storage.string(forKey: "qonversion.keys.userId")
        try storage.set(["premium": Qonversion.Entitlement(id: "premium", active: true, source: .appStore)], forKey: "qonversion.keys.entitlements")
        try storage.set(["id": "device_1"], forKey: "io.qonversion.sdk.storage.device")

        _ = QonversionAssembly(apiKey: "key-b", userDefaults: defaults)

        XCTAssertNil(try storage.object(forKey: "qonversion.keys.entitlements", dataType: [String: Qonversion.Entitlement].self),
                     "the previous project's entitlements must never be served to the new one")
        XCTAssertNil(storage.data(forKey: "io.qonversion.sdk.storage.device"),
                     "the device row belongs to the previous project — it must be created anew")
        XCTAssertNotNil(firstUserId)
        // A fresh uid, not merely a missing one: the wipe has to happen before
        // the uid seeding, or the new project runs the whole session on the
        // previous project's uid.
        let secondUserId: String? = storage.string(forKey: "qonversion.keys.userId")
        XCTAssertEqual(secondUserId?.hasPrefix("QON_"), true)
        XCTAssertNotEqual(secondUserId, firstUserId)
        XCTAssertEqual(storage.string(forKey: "qonversion.keys.originalUserId"), secondUserId)
        XCTAssertNil(storage.string(forKey: "qonversion.keys.identityExternalId"))
    }

    func testAFirstRunStillMigratesThePreviousSdkGeneration() throws {
        // No stored key at all: an install upgrading from the Objective-C SDK
        // must keep its user and its offline entitlements cache.
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        legacyDefaults.set("QON_legacy_user", forKey: legacyUserIdKey)
        let relation: Data = try NSKeyedArchiver.archivedData(withRootObject: ["pro": ["premium"]], requiringSecureCoding: false)
        legacyDefaults.set(relation, forKey: legacyRelationKey)

        _ = QonversionAssembly(apiKey: "key-a", userDefaults: defaults)

        let storage: LocalStorage = makeStorage(over: defaults)
        XCTAssertEqual(storage.string(forKey: "qonversion.keys.userId"), "QON_legacy_user")
        let migratedRelation: [String: [String]]? = try storage.object(forKey: "qonversion.keys.productsPermissions", dataType: [String: [String]].self)
        XCTAssertEqual(migratedRelation, ["pro": ["premium"]])
    }

    func testAKeyChangeCannotResurrectTheMigratedLegacyCache() throws {
        let defaults: UserDefaults = TestDefaults.makeIsolated()
        legacyDefaults.set("QON_legacy_user", forKey: legacyUserIdKey)
        let relation: Data = try NSKeyedArchiver.archivedData(withRootObject: ["pro": ["premium"]], requiringSecureCoding: false)
        legacyDefaults.set(relation, forKey: legacyRelationKey)
        _ = QonversionAssembly(apiKey: "key-a", userDefaults: defaults)

        _ = QonversionAssembly(apiKey: "key-b", userDefaults: defaults)

        let storage: LocalStorage = makeStorage(over: defaults)
        XCTAssertNil(try storage.object(forKey: "qonversion.keys.productsPermissions", dataType: [String: [String]].self))
        XCTAssertNotEqual(storage.string(forKey: "qonversion.keys.userId"), "QON_legacy_user")
    }
}
