//
//  LegacyPurchaseStateMigrationTests.swift
//  QonversionUnitTests
//
//  The fixtures are written in the GENUINE legacy format: NSKeyedArchiver in
//  its non-secure form, under the Objective-C class name (QONPurchaseOptions)
//  and with the archive keys the ObjC coder used (NSStringFromSelector of each
//  property). A hand-rolled fixture would prove nothing about reading what is
//  actually on users' devices.
//

import XCTest
@testable import Qonversion

final class LegacyPurchaseStateMigrationTests: XCTestCase {

    private var legacyDefaults: UserDefaults!
    private var hostDefaults: UserDefaults!
    private var targetDefaults: UserDefaults!
    private var storage: LocalStorage!

    private let legacyOptionsKey = "com.qonversion.keys.purchases.options"
    private let legacyHistoricalKey = "isHistoricalDataSynced"

    private let associationsKey = "qonversion.keys.purchaseAssociations"
    private let historicalKey = "qonversion.keys.historicalDataSynced"

    override func setUp() {
        super.setUp()
        legacyDefaults = TestDefaults.makeIsolated("legacy")
        hostDefaults = TestDefaults.makeIsolated("host")
        targetDefaults = TestDefaults.makeIsolated("target")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        storage = LocalStorage(userDefaults: targetDefaults, encoder: encoder, decoder: decoder)
    }

    override func tearDown() {
        legacyDefaults = nil
        hostDefaults = nil
        targetDefaults = nil
        storage = nil
        super.tearDown()
    }

    private func makeMigration() -> LegacyPurchaseStateMigration {
        let logger = LoggerWrapper()

        return LegacyPurchaseStateMigration(
            localStorage: storage,
            logger: logger,
            legacyDefaults: legacyDefaults,
            hostDefaults: hostDefaults
        )
    }

    /// Exactly what `NSKeyedArchiver.archivedDataWithRootObject:` produced.
    private func legacyArchive(of root: Any) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("QONPurchaseOptions", for: LegacyArchivedPurchaseOptions.self)
        archiver.encode(root, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        return archiver.encodedData
    }

    private func storedAssociations() throws -> [String: PurchaseAssociations] {
        return (try storage.object(forKey: associationsKey, dataType: [String: PurchaseAssociations].self)) ?? [:]
    }

    // MARK: - the purchase context

    func testLegacyPurchaseOptionsBecomePurchaseAssociations() throws {
        // The ObjC SDK removed the entry only after a SUCCESSFUL report, so
        // whatever is left belongs to a transaction it never finished — the one
        // the unfinished sweep re-reports on this very launch. Without the
        // context, it is re-reported with no attribution at all.
        let options = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["paywall_a"], screenUid: "scr_1")
        legacyDefaults.set(try legacyArchive(of: ["com.app.pro": options]), forKey: legacyOptionsKey)

        makeMigration().run()

        let migrated: PurchaseAssociations = try XCTUnwrap(try storedAssociations()["com.app.pro"])
        XCTAssertEqual(migrated.contextKeys, ["paywall_a"])
        XCTAssertEqual(migrated.screenUid, "scr_1")
    }

    func testEveryPendingProductIsCarriedOver() throws {
        let first = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["a"], screenUid: nil)
        let second = LegacyArchivedPurchaseOptions(quantity: 2, contextKeys: nil, screenUid: "scr_2")
        legacyDefaults.set(try legacyArchive(of: ["com.app.pro": first, "com.app.plus": second]), forKey: legacyOptionsKey)

        makeMigration().run()

        let migrated: [String: PurchaseAssociations] = try storedAssociations()
        XCTAssertEqual(Set(migrated.keys), ["com.app.pro", "com.app.plus"])
        XCTAssertEqual(migrated["com.app.plus"]?.screenUid, "scr_2")
        XCTAssertNil(migrated["com.app.plus"]?.contextKeys)
    }

    func testTheLegacyPurchaseOptionsKeyIsConsumed() throws {
        let options = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["a"], screenUid: nil)
        legacyDefaults.set(try legacyArchive(of: ["com.app.pro": options]), forKey: legacyOptionsKey)

        makeMigration().run()

        XCTAssertNil(legacyDefaults.object(forKey: legacyOptionsKey), "a consumed key must not be re-migrated on every launch forever")
    }

    func testAnAssociationThisSdkAlreadyHasIsNotOverwritten() throws {
        let current = PurchaseAssociations(contextKeys: ["current"], screenUid: "scr_now")
        try storage.set(["com.app.pro": current], forKey: associationsKey)
        let options = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["stale"], screenUid: "scr_old")
        legacyDefaults.set(try legacyArchive(of: ["com.app.pro": options]), forKey: legacyOptionsKey)

        makeMigration().run()

        XCTAssertEqual(try storedAssociations()["com.app.pro"]?.contextKeys, ["current"], "this SDK's own answer always wins")
    }

    func testUndecodableOptionsAreDroppedRatherThanRetriedForever() {
        legacyDefaults.set(Data("not an archive".utf8), forKey: legacyOptionsKey)

        makeMigration().run()

        XCTAssertNil(legacyDefaults.object(forKey: legacyOptionsKey))
    }

    func testNothingIsWrittenWhenThereIsNoLegacyData() throws {
        makeMigration().run()

        XCTAssertNil(try storage.object(forKey: associationsKey, dataType: [String: PurchaseAssociations].self))
    }

    // MARK: - the historical sync flag

    func testTheHistoricalSyncFlagIsMigrated() {
        // Hosts are documented to call syncHistoricalData() on every start. On
        // the ObjC SDK the flag made that a no-op; without the flag, the first
        // Swift launch re-sends the entire purchase history.
        legacyDefaults.set(true, forKey: legacyHistoricalKey)

        makeMigration().run()

        XCTAssertTrue(storage.bool(forKey: historicalKey))
        XCTAssertNil(legacyDefaults.object(forKey: legacyHistoricalKey))
    }

    func testAnUnsyncedInstallIsNotMarkedSynced() {
        legacyDefaults.set(false, forKey: legacyHistoricalKey)

        makeMigration().run()

        XCTAssertFalse(storage.bool(forKey: historicalKey), "an install that never synced must still sync")
    }

    func testAFlagThisSdkAlreadySetIsNotClearedByTheMigration() {
        storage.set(bool: true, forKey: historicalKey)

        makeMigration().run()

        XCTAssertTrue(storage.bool(forKey: historicalKey))
    }

    // MARK: - the host-provided defaults (the ObjC dual write)

    func testTheHostProvidedDefaultsAreThePreferredSource() throws {
        // QNUserDefaultsStorage wrote every blob to BOTH the suite and the
        // host's customUserDefaults, and read the custom one first.
        let hostOptions = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["from_host"], screenUid: nil)
        let suiteOptions = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["from_suite"], screenUid: nil)
        hostDefaults.set(try legacyArchive(of: ["com.app.pro": hostOptions]), forKey: legacyOptionsKey)
        legacyDefaults.set(try legacyArchive(of: ["com.app.pro": suiteOptions]), forKey: legacyOptionsKey)

        makeMigration().run()

        XCTAssertEqual(try storedAssociations()["com.app.pro"]?.contextKeys, ["from_host"])
    }

    func testTheHostProvidedDefaultsAreReadWhenTheSuiteIsEmpty() throws {
        let options = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["from_host"], screenUid: nil)
        hostDefaults.set(try legacyArchive(of: ["com.app.pro": options]), forKey: legacyOptionsKey)

        makeMigration().run()

        XCTAssertEqual(try storedAssociations()["com.app.pro"]?.contextKeys, ["from_host"])
    }

    func testTheHostProvidedDefaultsAreCleanedToo() throws {
        let options = LegacyArchivedPurchaseOptions(quantity: 1, contextKeys: ["a"], screenUid: nil)
        hostDefaults.set(try legacyArchive(of: ["com.app.pro": options]), forKey: legacyOptionsKey)
        hostDefaults.set(true, forKey: legacyHistoricalKey)

        makeMigration().run()

        XCTAssertNil(hostDefaults.object(forKey: legacyOptionsKey), "with an app-group suite the blob would otherwise survive forever")
        XCTAssertNil(hostDefaults.object(forKey: legacyHistoricalKey))
    }

    func testTheHistoricalFlagIsReadFromTheHostDefaultsToo() {
        hostDefaults.set(true, forKey: legacyHistoricalKey)

        makeMigration().run()

        XCTAssertTrue(storage.bool(forKey: historicalKey))
    }
}

// MARK: - the other migrations reach the host defaults as well

final class LegacyMigrationHostDefaultsTests: XCTestCase {

    private var legacyDefaults: UserDefaults!
    private var hostDefaults: UserDefaults!
    private var targetDefaults: UserDefaults!
    private var storage: LocalStorage!

    private let legacyQueueKey = "com.qonversion.keys.requests.stored.purchases"
    private let legacyRelationKey = "com.qonversion.keys.products.permissions.relation"
    private let legacyEntitlementsKey = "com.qonversion.keys.entitlements"
    private let legacyTimestampKey = "com.qonversion.keys.permissions.timestamp"
    private let legacyTransferredKey = "com.qonversion.keys.entitlements.transfered"
    private let productPermissionsKey = "qonversion.keys.productsPermissions"

    override func setUp() {
        super.setUp()
        legacyDefaults = TestDefaults.makeIsolated("legacy")
        hostDefaults = TestDefaults.makeIsolated("host")
        targetDefaults = TestDefaults.makeIsolated("target")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        storage = LocalStorage(userDefaults: targetDefaults, encoder: encoder, decoder: decoder)
    }

    override func tearDown() {
        legacyDefaults = nil
        hostDefaults = nil
        targetDefaults = nil
        storage = nil
        super.tearDown()
    }

    func testTheQueueMigrationCleansTheHostProvidedDefaults() {
        legacyDefaults.set(Data([0x01]), forKey: legacyQueueKey)
        hostDefaults.set(Data([0x01]), forKey: legacyQueueKey)

        let migration = LegacyPurchasesQueueMigration(legacyDefaults: legacyDefaults, hostDefaults: hostDefaults)
        migration.run()

        XCTAssertNil(legacyDefaults.object(forKey: legacyQueueKey))
        XCTAssertNil(hostDefaults.object(forKey: legacyQueueKey), "an app-group copy of a dead queue would never be reclaimed")
    }

    func testTheEntitlementsMigrationReadsTheHostProvidedDefaultsFirst() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(["com.app.pro": ["premium"]], forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        hostDefaults.set(archiver.encodedData, forKey: legacyRelationKey)

        let logger = LoggerWrapper()
        let migration = LegacyEntitlementsMigration(
            localStorage: storage,
            logger: logger,
            legacyDefaults: legacyDefaults,
            hostDefaults: hostDefaults
        )
        migration.run()

        let relations: [String: [String]] = try XCTUnwrap(try storage.object(forKey: productPermissionsKey, dataType: [String: [String]].self))
        XCTAssertEqual(relations["com.app.pro"], ["premium"])
    }

    func testTheEntitlementsMigrationCleansTheHostProvidedDefaults() {
        for key in [legacyRelationKey, legacyEntitlementsKey, legacyTimestampKey, legacyTransferredKey] {
            hostDefaults.set(Data([0x01]), forKey: key)
        }

        let logger = LoggerWrapper()
        let migration = LegacyEntitlementsMigration(
            localStorage: storage,
            logger: logger,
            legacyDefaults: legacyDefaults,
            hostDefaults: hostDefaults
        )
        migration.run()

        for key in [legacyRelationKey, legacyEntitlementsKey, legacyTimestampKey, legacyTransferredKey] {
            XCTAssertNil(hostDefaults.object(forKey: key), "\(key) survived in the host-provided defaults")
        }
    }
}
