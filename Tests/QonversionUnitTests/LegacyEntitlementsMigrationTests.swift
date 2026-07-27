//
//  LegacyEntitlementsMigrationTests.swift
//  QonversionUnitTests
//
//  The fixtures here are written in the GENUINE legacy format: NSKeyedArchiver
//  in its non-secure form, under the Objective-C class names (QONEntitlement,
//  QONTransaction) and with the archive keys the ObjC coders used
//  (NSStringFromSelector of each property). A hand-rolled JSON fixture would
//  prove nothing about reading what is actually on users' devices.
//

import XCTest
@testable import Qonversion

final class LegacyEntitlementsMigrationTests: XCTestCase {

    private let suiteName = "qonversion.localstorage.main"
    private var legacyDefaults: UserDefaults!
    private var storage: LocalStorage!
    private var targetDefaults: UserDefaults!

    private let entitlementsKey = "qonversion.keys.entitlements"
    private let entitlementsTimestampKey = "qonversion.keys.entitlementsTimestamp"
    private let backendTimestampKey = "qonversion.keys.entitlementsBackendTimestamp"
    private let productPermissionsKey = "qonversion.keys.productsPermissions"

    private let legacyEntitlementsKey = "com.qonversion.keys.entitlements"
    private let legacyTimestampKey = "com.qonversion.keys.permissions.timestamp"
    private let legacyRelationKey = "com.qonversion.keys.products.permissions.relation"
    private let legacyTransferredKey = "com.qonversion.keys.entitlements.transfered"

    override func setUp() {
        super.setUp()
        legacyDefaults = UserDefaults(suiteName: suiteName)
        legacyDefaults.removePersistentDomain(forName: suiteName)
        targetDefaults = TestDefaults.makeIsolated()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        storage = LocalStorage(userDefaults: targetDefaults, encoder: encoder, decoder: decoder)
    }

    override func tearDown() {
        legacyDefaults.removePersistentDomain(forName: suiteName)
        legacyDefaults = nil
        targetDefaults = nil
        storage = nil
        super.tearDown()
    }

    private func makeMigration() -> LegacyEntitlementsMigration {
        let logger = LoggerWrapper()

        return LegacyEntitlementsMigration(localStorage: storage, logger: logger, legacyDefaults: legacyDefaults)
    }

    /// Exactly what `NSKeyedArchiver.archivedDataWithRootObject:` produced:
    /// non-secure, and with the shims mapped back onto the ObjC class names.
    private func legacyArchive(of root: Any) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("QONEntitlement", for: LegacyArchivedEntitlement.self)
        archiver.setClassName("QONTransaction", for: LegacyArchivedTransaction.self)
        archiver.encode(root, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        return archiver.encodedData
    }

    // MARK: - product -> entitlements relation

    func testTheProductMappingIsMigrated() throws {
        // The mapping is what makes OFFLINE local entitlement calculation
        // possible: without it an upgrading user opening the app with no
        // network has no access at all until the first successful request.
        let relations: NSDictionary = ["pro": ["premium", "no_ads"], "consumable": []]
        legacyDefaults.set(try legacyArchive(of: relations), forKey: legacyRelationKey)

        let outcome = makeMigration().run()

        XCTAssertEqual(outcome.migratedRelations, 2)
        let migrated: [String: [String]]? = try storage.object(forKey: productPermissionsKey, dataType: [String: [String]].self)
        XCTAssertEqual(migrated, ["pro": ["premium", "no_ads"], "consumable": []])
    }

    func testTheProductMappingIsNotMigratedOverAnExistingOne() throws {
        try storage.set(["already": ["here"]], forKey: productPermissionsKey)
        let relations: NSDictionary = ["pro": ["premium"]]
        legacyDefaults.set(try legacyArchive(of: relations), forKey: legacyRelationKey)

        _ = makeMigration().run()

        let migrated: [String: [String]]? = try storage.object(forKey: productPermissionsKey, dataType: [String: [String]].self)
        XCTAssertEqual(migrated, ["already": ["here"]], "this SDK's own data always wins")
    }

    // MARK: - entitlements

    func testAnArchivedEntitlementIsMigratedWithEveryField() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let expires = Date(timeIntervalSince1970: 1_702_600_000)
        let transaction = LegacyArchivedTransaction(
            originalTransactionId: "orig-1",
            transactionId: "tx-1",
            offerCode: "CODE",
            transactionDate: started,
            expirationDate: expires,
            transactionRevocationDate: nil,
            promoOfferId: "promo-1",
            environment: 0,        // QONTransactionEnvironmentSandbox
            ownershipType: 1,      // QONTransactionOwnershipTypeFamilySharing
            type: 3                // QONTransactionTypeTrialStarted
        )
        let entitlement = LegacyArchivedEntitlement(
            entitlementID: "premium",
            productID: "pro",
            isActive: true,
            renewState: 2,         // QONEntitlementRenewStateCancelled
            source: 3,             // QONEntitlementSourceStripe
            startedDate: started,
            expirationDate: expires,
            renewsCount: 18,
            trialStartDate: started,
            firstPurchaseDate: started,
            lastPurchaseDate: started,
            autoRenewDisableDate: expires,
            lastActivatedOfferCode: "CODE",
            grantType: 2,          // QONEntitlementGrantTypeOfferCode
            transactions: [transaction]
        )
        let root: NSDictionary = ["premium": entitlement]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)
        legacyDefaults.set(1_700_000_500.0, forKey: legacyTimestampKey)

        let outcome = makeMigration().run()

        XCTAssertEqual(outcome.migratedEntitlements, 1)
        let migrated: [String: Qonversion.Entitlement]? = try storage.object(forKey: entitlementsKey, dataType: [String: Qonversion.Entitlement].self)
        let premium = try XCTUnwrap(migrated?["premium"])
        XCTAssertEqual(premium.id, "premium")
        XCTAssertTrue(premium.active)
        XCTAssertEqual(premium.source, .stripe)
        XCTAssertEqual(premium.renewState, .canceled)
        XCTAssertEqual(premium.grantType, .offerCode)
        XCTAssertEqual(premium.productId, "pro")
        XCTAssertEqual(premium.renewsCount, 18)
        XCTAssertEqual(premium.startedDate, started)
        XCTAssertEqual(premium.expirationDate, expires)
        XCTAssertEqual(premium.trialStartDate, started)
        XCTAssertEqual(premium.firstPurchaseDate, started)
        XCTAssertEqual(premium.lastPurchaseDate, started)
        XCTAssertEqual(premium.autoRenewDisableDate, expires)
        XCTAssertEqual(premium.lastActivatedOfferCode, "CODE")

        let migratedTransaction = try XCTUnwrap(premium.transactions.first)
        XCTAssertEqual(migratedTransaction.transactionId, "tx-1")
        XCTAssertEqual(migratedTransaction.originalTransactionId, "orig-1")
        XCTAssertEqual(migratedTransaction.offerCode, "CODE")
        XCTAssertEqual(migratedTransaction.promoOfferId, "promo-1")
        XCTAssertEqual(migratedTransaction.environment, .sandbox)
        XCTAssertEqual(migratedTransaction.ownershipType, .familyShared)
        XCTAssertEqual(migratedTransaction.type, .trialStarted)
    }

    func testTheLegacyTimestampSeedsBothClocks() throws {
        let root: NSDictionary = ["premium": LegacyArchivedEntitlement(entitlementID: "premium")]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)
        legacyDefaults.set(1_700_000_500.0, forKey: legacyTimestampKey)

        _ = makeMigration().run()

        // The legacy cache only ever held backend answers, so it seeds the
        // backend clock too — otherwise the configured cache lifetime would
        // measure from the wrong moment.
        XCTAssertEqual(storage.double(forKey: entitlementsTimestampKey), 1_700_000_500.0)
        XCTAssertEqual(storage.double(forKey: backendTimestampKey), 1_700_000_500.0)
    }

    func testEveryEntitlementSourceAndStateIsMapped() throws {
        let root: NSDictionary = [
            "a": LegacyArchivedEntitlement(entitlementID: "a", isActive: true, renewState: -1, source: -1),
            "b": LegacyArchivedEntitlement(entitlementID: "b", isActive: true, renewState: 0, source: 1),
            "c": LegacyArchivedEntitlement(entitlementID: "c", isActive: true, renewState: 1, source: 2),
            "d": LegacyArchivedEntitlement(entitlementID: "d", isActive: false, renewState: 3, source: 4)
        ]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)

        _ = makeMigration().run()

        let migrated: [String: Qonversion.Entitlement] = try XCTUnwrap(
            storage.object(forKey: entitlementsKey, dataType: [String: Qonversion.Entitlement].self)
        )
        XCTAssertEqual(migrated["a"]?.source, .unknown)
        XCTAssertEqual(migrated["a"]?.renewState, .nonRenewable)
        XCTAssertEqual(migrated["b"]?.source, .appStore)
        XCTAssertEqual(migrated["b"]?.renewState, .unknown)
        XCTAssertEqual(migrated["c"]?.source, .playStore)
        XCTAssertEqual(migrated["c"]?.renewState, .willRenew)
        XCTAssertEqual(migrated["d"]?.source, .manual)
        XCTAssertEqual(migrated["d"]?.renewState, .billingIssue)
        XCTAssertEqual(migrated["d"]?.active, false)
    }

    func testAnEntitlementWithoutItsOwnIdTakesTheDictionaryKey() throws {
        let root: NSDictionary = ["premium": LegacyArchivedEntitlement(entitlementID: nil)]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)

        _ = makeMigration().run()

        let migrated: [String: Qonversion.Entitlement]? = try storage.object(forKey: entitlementsKey, dataType: [String: Qonversion.Entitlement].self)
        XCTAssertNotNil(migrated?["premium"])
    }

    func testEntitlementsAreNotMigratedOverExistingOnes() throws {
        let existing: [String: Qonversion.Entitlement] = ["mine": Qonversion.Entitlement(id: "mine", active: true, source: .appStore)]
        try storage.set(existing, forKey: entitlementsKey)
        let root: NSDictionary = ["premium": LegacyArchivedEntitlement(entitlementID: "premium")]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)

        _ = makeMigration().run()

        let migrated: [String: Qonversion.Entitlement]? = try storage.object(forKey: entitlementsKey, dataType: [String: Qonversion.Entitlement].self)
        XCTAssertNil(migrated?["premium"])
        XCTAssertNotNil(migrated?["mine"], "this SDK's own data always wins")
    }

    // MARK: - consuming the keys

    func testEveryLegacyKeyIsConsumed() throws {
        let root: NSDictionary = ["premium": LegacyArchivedEntitlement(entitlementID: "premium")]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)
        legacyDefaults.set(try legacyArchive(of: ["pro": ["premium"]] as NSDictionary), forKey: legacyRelationKey)
        legacyDefaults.set(1_700_000_500.0, forKey: legacyTimestampKey)
        legacyDefaults.set(true, forKey: legacyTransferredKey)

        _ = makeMigration().run()

        XCTAssertNil(legacyDefaults.object(forKey: legacyEntitlementsKey))
        XCTAssertNil(legacyDefaults.object(forKey: legacyRelationKey))
        XCTAssertNil(legacyDefaults.object(forKey: legacyTimestampKey))
        XCTAssertNil(legacyDefaults.object(forKey: legacyTransferredKey))
    }

    func testUndecodableDataIsConsumedAndReported() {
        // Not retried on every launch forever, and not silently either.
        legacyDefaults.set(Data([0x01, 0x02, 0x03]), forKey: legacyEntitlementsKey)
        legacyDefaults.set(Data([0x04, 0x05]), forKey: legacyRelationKey)

        let outcome = makeMigration().run()

        XCTAssertTrue(outcome.entitlementsDecodeFailed)
        XCTAssertTrue(outcome.relationDecodeFailed)
        XCTAssertEqual(outcome.migratedEntitlements, 0)
        XCTAssertNil(legacyDefaults.object(forKey: legacyEntitlementsKey))
        XCTAssertNil(legacyDefaults.object(forKey: legacyRelationKey))
    }

    func testAnEmptySuiteIsHarmless() {
        let outcome = makeMigration().run()

        XCTAssertEqual(outcome, LegacyEntitlementsMigration.Outcome())
    }

    func testRunningTwiceIsHarmless() throws {
        let root: NSDictionary = ["premium": LegacyArchivedEntitlement(entitlementID: "premium")]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)
        let migration = makeMigration()

        _ = migration.run()
        let second = migration.run()

        XCTAssertEqual(second, LegacyEntitlementsMigration.Outcome())
        let migrated: [String: Qonversion.Entitlement]? = try storage.object(forKey: entitlementsKey, dataType: [String: Qonversion.Entitlement].self)
        XCTAssertNotNil(migrated?["premium"], "the first run's result survives the second")
    }

    // MARK: - the migrated data is actually usable

    func testTheMigratedCacheIsServedByTheEntitlementsManager() async throws {
        let expires = Date().addingTimeInterval(3600)
        let root: NSDictionary = [
            "premium": LegacyArchivedEntitlement(entitlementID: "premium", productID: "pro", isActive: true, source: 1, expirationDate: expires)
        ]
        legacyDefaults.set(try legacyArchive(of: root), forKey: legacyEntitlementsKey)
        legacyDefaults.set(Date().timeIntervalSince1970, forKey: legacyTimestampKey)
        _ = makeMigration().run()

        let service = MockEntitlementsService()
        service.error = QonversionError(type: .internal)
        let userManager = MockUserManager()
        userManager.user = try? JSONDecoder.qonversionTest.decode(
            Qonversion.User.self,
            from: Data(#"{"id": "QON_upgraded", "created_at": "2023-11-14T22:13:20Z", "environment": "prod"}"#.utf8))
        let storeKitFacade = MockStoreKitFacade()
        let productsDataSource = MockProductsManager()
        let userIdProvider = InternalConfig(userId: "QON_upgraded")
        let logger = LoggerWrapper()
        let manager = EntitlementsManager(
            entitlementsService: service,
            storeKitFacade: storeKitFacade,
            productsDataSource: productsDataSource,
            userManager: userManager,
            userIdProvider: userIdProvider,
            localStorage: storage,
            cacheLifetime: Qonversion.EntitlementsCacheLifetime.month.seconds,
            logger: logger
        )

        let entitlements = try await manager.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true,
                       "an upgrading user opening the app offline must keep their access")
    }
}
