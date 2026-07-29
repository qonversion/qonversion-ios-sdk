//
//  LegacyEntitlementsMigration.swift
//  Qonversion
//

import Foundation

/// Carries the previous SDK generation's entitlements cache into this one.
///
/// The Objective-C SDK kept three things in its own UserDefaults suite
/// (`qonversion.localstorage.main`):
///
///   * `com.qonversion.keys.products.permissions.relation` — the product →
///     entitlements mapping, an `NSKeyedArchiver` archive of a plain plist
///     graph (`[String: [String]]`). This is what makes the OFFLINE local
///     entitlement calculation possible, so an upgrading user who opens the
///     app without a network keeps their access instead of losing it until
///     the first successful request.
///   * `com.qonversion.keys.entitlements` — an `NSKeyedArchiver` archive of
///     `NSDictionary<NSString *, QONEntitlement *>`. Custom Objective-C
///     classes, which is why they are decoded here through Swift `NSCoding`
///     shims registered under the archived class names: the archive keys are
///     the property names (`NSStringFromSelector`), so a key-compatible shim
///     reads them exactly.
///   * `com.qonversion.keys.permissions.timestamp` — a plain double, when the
///     backend last answered. It seeds both timestamps this SDK keeps, because
///     the legacy cache only ever held backend answers.
///
/// Nothing is overwritten: a value this SDK has already written always wins.
/// The legacy keys are consumed either way — partially decodable data must not
/// be retried on every launch forever, and the first successful backend answer
/// replaces all of it anyway.
struct LegacyEntitlementsMigration {

    /// What the run actually managed to carry over. Returned (and logged) so
    /// the outcome is observable rather than guessed at.
    struct Outcome: Equatable {
        var migratedRelations: Int = 0
        var migratedEntitlements: Int = 0
        var skippedEntitlements: Int = 0
        var relationDecodeFailed: Bool = false
        var entitlementsDecodeFailed: Bool = false
    }

    private enum LegacyKeys: String {
        case suiteName = "qonversion.localstorage.main"
        case entitlements = "com.qonversion.keys.entitlements"
        case entitlementsTimestamp = "com.qonversion.keys.permissions.timestamp"
        case productsPermissionsRelation = "com.qonversion.keys.products.permissions.relation"
        case entitlementsTransferred = "com.qonversion.keys.entitlements.transfered"
    }

    /// Owned by EntitlementsManager and ProductsManager; repeated here because
    /// they are file-private there. Changing one without the other breaks the
    /// migration silently, so both sides carry this note.
    private enum TargetKeys: String {
        case entitlements = "qonversion.keys.entitlements"
        case entitlementsTimestamp = "qonversion.keys.entitlementsTimestamp"
        case entitlementsBackendTimestamp = "qonversion.keys.entitlementsBackendTimestamp"
        case productPermissions = "qonversion.keys.productsPermissions"
    }

    private let legacyDefaults: UserDefaults?
    private let hostDefaults: UserDefaults?
    private let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper

    init(
        localStorage: LocalStorageInterface,
        logger: LoggerWrapper,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: LegacyEntitlementsMigration.legacySuiteName),
        hostDefaults: UserDefaults? = nil
    ) {
        self.localStorage = localStorage
        self.logger = logger
        self.legacyDefaults = legacyDefaults
        self.hostDefaults = hostDefaults
    }

    static var legacySuiteName: String { LegacyKeys.suiteName.rawValue }

    /// The host-provided defaults first, mirroring `QNUserDefaultsStorage`,
    /// which wrote every blob to both and read the custom one first.
    private var sources: [UserDefaults] {
        return [hostDefaults, legacyDefaults].compactMap { $0 }
    }

    @discardableResult
    func run() -> Outcome {
        let legacySources: [UserDefaults] = sources
        guard !legacySources.isEmpty else { return Outcome() }

        var outcome = Outcome()
        migrateProductPermissions(from: legacySources, into: &outcome)
        migrateEntitlements(from: legacySources, into: &outcome)

        LegacyDefaults.remove(LegacyKeys.productsPermissionsRelation.rawValue, from: legacySources)
        LegacyDefaults.remove(LegacyKeys.entitlements.rawValue, from: legacySources)
        LegacyDefaults.remove(LegacyKeys.entitlementsTimestamp.rawValue, from: legacySources)
        LegacyDefaults.remove(LegacyKeys.entitlementsTransferred.rawValue, from: legacySources)

        if outcome != Outcome() {
            logger.info("Migrated the previous SDK generation's cache: \(outcome.migratedRelations) product mappings, \(outcome.migratedEntitlements) entitlements.")
        }

        return outcome
    }

    // MARK: - Private

    private func migrateProductPermissions(from sources: [UserDefaults], into outcome: inout Outcome) {
        guard let data: Data = LegacyDefaults.data(forKey: LegacyKeys.productsPermissionsRelation.rawValue, in: sources) else { return }
        // Never over an answer this SDK already has.
        let existing: [String: [String]]? = try? localStorage.object(forKey: TargetKeys.productPermissions.rawValue, dataType: [String: [String]].self)
        guard existing == nil else { return }

        guard let root = Self.unarchivedRoot(from: data, classMappings: [:]) else {
            outcome.relationDecodeFailed = true
            return
        }
        guard let relations = root as? [String: [String]], !relations.isEmpty else {
            outcome.relationDecodeFailed = true
            return
        }

        do {
            try localStorage.set(relations, forKey: TargetKeys.productPermissions.rawValue)
            outcome.migratedRelations = relations.count
        } catch {
            logger.warning("Failed to store the migrated product mappings: " + error.message)
        }
    }

    private func migrateEntitlements(from sources: [UserDefaults], into outcome: inout Outcome) {
        guard let data: Data = LegacyDefaults.data(forKey: LegacyKeys.entitlements.rawValue, in: sources) else { return }
        let existing: [String: Qonversion.Entitlement]? = try? localStorage.object(forKey: TargetKeys.entitlements.rawValue, dataType: [String: Qonversion.Entitlement].self)
        guard existing == nil else { return }

        let mappings: [String: AnyClass] = [
            "QONEntitlement": LegacyArchivedEntitlement.self,
            "QONTransaction": LegacyArchivedTransaction.self
        ]
        guard let root = Self.unarchivedRoot(from: data, classMappings: mappings) else {
            outcome.entitlementsDecodeFailed = true
            return
        }
        guard let archived = root as? [String: LegacyArchivedEntitlement] else {
            outcome.entitlementsDecodeFailed = true
            return
        }

        var migrated: [String: Qonversion.Entitlement] = [:]
        for (key, value) in archived {
            guard let entitlement: Qonversion.Entitlement = value.entitlement(fallbackId: key) else {
                outcome.skippedEntitlements += 1
                continue
            }

            migrated[entitlement.id] = entitlement
        }
        guard !migrated.isEmpty else { return }

        do {
            try localStorage.set(migrated, forKey: TargetKeys.entitlements.rawValue)
            // The legacy cache only ever held backend answers, so its
            // timestamp seeds both clocks this SDK keeps. A missing or
            // nonsensical timestamp falls back to "now": the data is real, and
            // the alternative is discarding it.
            let legacyTimestamp: Double = LegacyDefaults.double(forKey: LegacyKeys.entitlementsTimestamp.rawValue, in: sources)
            let timestamp: Double = legacyTimestamp > 0 ? legacyTimestamp : Date().timeIntervalSince1970
            localStorage.set(double: timestamp, forKey: TargetKeys.entitlementsTimestamp.rawValue)
            localStorage.set(double: timestamp, forKey: TargetKeys.entitlementsBackendTimestamp.rawValue)
            outcome.migratedEntitlements = migrated.count
        } catch {
            logger.warning("Failed to store the migrated entitlements: " + error.message)
        }
    }

    /// `NSKeyedArchiver.archivedDataWithRootObject:` (which is what wrote these
    /// payloads) is the non-secure form, so secure coding has to be off and the
    /// root read by key.
    private static func unarchivedRoot(from data: Data, classMappings: [String: AnyClass]) -> Any? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }

        unarchiver.requiresSecureCoding = false
        for mapping in classMappings {
            // Bound explicitly: destructuring the pair infers AnyClass, which
            // the compiler warns about (and the house style asks for the
            // annotation anyway).
            let shimClass: AnyClass = mapping.value
            unarchiver.setClass(shimClass, forClassName: mapping.key)
        }

        let root: Any? = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()

        return root
    }
}

// MARK: - Archived shapes

/// Key-compatible stand-in for the Objective-C `QONEntitlement`: the archive
/// keys are the property names, so decoding through this reads the real
/// payload. Only ever used for reading (and, in tests, for writing fixtures in
/// the genuine legacy format).
final class LegacyArchivedEntitlement: NSObject, NSCoding {

    let entitlementID: String?
    let productID: String?
    let isActive: Bool
    let renewState: Int
    let source: Int
    let startedDate: Date?
    let expirationDate: Date?
    let renewsCount: Int
    let trialStartDate: Date?
    let firstPurchaseDate: Date?
    let lastPurchaseDate: Date?
    let autoRenewDisableDate: Date?
    let lastActivatedOfferCode: String?
    let grantType: Int
    let transactions: [LegacyArchivedTransaction]

    init(
        entitlementID: String?,
        productID: String? = nil,
        isActive: Bool = true,
        renewState: Int = 0,
        source: Int = 1,
        startedDate: Date? = nil,
        expirationDate: Date? = nil,
        renewsCount: Int = 0,
        trialStartDate: Date? = nil,
        firstPurchaseDate: Date? = nil,
        lastPurchaseDate: Date? = nil,
        autoRenewDisableDate: Date? = nil,
        lastActivatedOfferCode: String? = nil,
        grantType: Int = 0,
        transactions: [LegacyArchivedTransaction] = []
    ) {
        self.entitlementID = entitlementID
        self.productID = productID
        self.isActive = isActive
        self.renewState = renewState
        self.source = source
        self.startedDate = startedDate
        self.expirationDate = expirationDate
        self.renewsCount = renewsCount
        self.trialStartDate = trialStartDate
        self.firstPurchaseDate = firstPurchaseDate
        self.lastPurchaseDate = lastPurchaseDate
        self.autoRenewDisableDate = autoRenewDisableDate
        self.lastActivatedOfferCode = lastActivatedOfferCode
        self.grantType = grantType
        self.transactions = transactions
    }

    init?(coder: NSCoder) {
        entitlementID = coder.decodeObject(forKey: "entitlementID") as? String
        productID = coder.decodeObject(forKey: "productID") as? String
        isActive = coder.decodeBool(forKey: "isActive")
        renewState = coder.decodeInteger(forKey: "renewState")
        source = coder.decodeInteger(forKey: "source")
        startedDate = coder.decodeObject(forKey: "startedDate") as? Date
        expirationDate = coder.decodeObject(forKey: "expirationDate") as? Date
        renewsCount = coder.decodeInteger(forKey: "renewsCount")
        trialStartDate = coder.decodeObject(forKey: "trialStartDate") as? Date
        firstPurchaseDate = coder.decodeObject(forKey: "firstPurchaseDate") as? Date
        lastPurchaseDate = coder.decodeObject(forKey: "lastPurchaseDate") as? Date
        autoRenewDisableDate = coder.decodeObject(forKey: "autoRenewDisableDate") as? Date
        lastActivatedOfferCode = coder.decodeObject(forKey: "lastActivatedOfferCode") as? String
        grantType = coder.decodeInteger(forKey: "grantType")
        transactions = coder.decodeObject(forKey: "transactions") as? [LegacyArchivedTransaction] ?? []
    }

    func encode(with coder: NSCoder) {
        coder.encode(entitlementID, forKey: "entitlementID")
        coder.encode(productID, forKey: "productID")
        coder.encode(isActive, forKey: "isActive")
        coder.encode(renewState, forKey: "renewState")
        coder.encode(source, forKey: "source")
        coder.encode(startedDate, forKey: "startedDate")
        coder.encode(expirationDate, forKey: "expirationDate")
        coder.encode(renewsCount, forKey: "renewsCount")
        coder.encode(lastActivatedOfferCode, forKey: "lastActivatedOfferCode")
        coder.encode(trialStartDate, forKey: "trialStartDate")
        coder.encode(firstPurchaseDate, forKey: "firstPurchaseDate")
        coder.encode(lastPurchaseDate, forKey: "lastPurchaseDate")
        coder.encode(autoRenewDisableDate, forKey: "autoRenewDisableDate")
        coder.encode(grantType, forKey: "grantType")
        coder.encode(transactions, forKey: "transactions")
    }

    /// The dictionary key is the entitlement id in the legacy format too, so
    /// it stands in when the archived object lost its own.
    func entitlement(fallbackId: String) -> Qonversion.Entitlement? {
        let identifier: String = (entitlementID?.isEmpty == false ? entitlementID : nil) ?? fallbackId
        guard !identifier.isEmpty else { return nil }

        return Qonversion.Entitlement(
            id: identifier,
            active: isActive,
            source: Self.source(from: source),
            renewState: Self.renewState(from: renewState),
            startedDate: startedDate,
            expirationDate: expirationDate,
            productId: productID,
            grantType: Self.grantType(from: grantType),
            renewsCount: renewsCount,
            trialStartDate: trialStartDate,
            firstPurchaseDate: firstPurchaseDate,
            lastPurchaseDate: lastPurchaseDate,
            autoRenewDisableDate: autoRenewDisableDate,
            lastActivatedOfferCode: lastActivatedOfferCode,
            transactions: transactions.map { $0.storeTransaction() }
        )
    }

    /// QONEntitlementSource: unknown -1, appStore 1, playStore 2, stripe 3,
    /// manual 4 (there is no 0).
    static func source(from raw: Int) -> Qonversion.Entitlement.Source {
        switch raw {
        case 1:
            return .appStore
        case 2:
            return .playStore
        case 3:
            return .stripe
        case 4:
            return .manual
        default:
            return .unknown
        }
    }

    /// QONEntitlementRenewState: nonRenewable -1, unknown 0, willRenew 1,
    /// cancelled 2, billingIssue 3.
    static func renewState(from raw: Int) -> Qonversion.Entitlement.RenewState {
        switch raw {
        case -1:
            return .nonRenewable
        case 1:
            return .willRenew
        case 2:
            return .canceled
        case 3:
            return .billingIssue
        default:
            return .unknown
        }
    }

    /// QONEntitlementGrantType: purchase 0, familySharing 1, offerCode 2,
    /// manual 3.
    static func grantType(from raw: Int) -> Qonversion.Entitlement.GrantType {
        switch raw {
        case 1:
            return .familySharing
        case 2:
            return .offerCode
        case 3:
            return .manual
        default:
            return .purchase
        }
    }
}

/// Key-compatible stand-in for the Objective-C `QONTransaction`.
final class LegacyArchivedTransaction: NSObject, NSCoding {

    let originalTransactionId: String?
    let transactionId: String?
    let offerCode: String?
    let transactionDate: Date?
    let expirationDate: Date?
    let transactionRevocationDate: Date?
    let promoOfferId: String?
    let environment: Int
    let ownershipType: Int
    let type: Int

    init(
        originalTransactionId: String? = nil,
        transactionId: String? = nil,
        offerCode: String? = nil,
        transactionDate: Date? = nil,
        expirationDate: Date? = nil,
        transactionRevocationDate: Date? = nil,
        promoOfferId: String? = nil,
        environment: Int = 1,
        ownershipType: Int = 0,
        type: Int = 0
    ) {
        self.originalTransactionId = originalTransactionId
        self.transactionId = transactionId
        self.offerCode = offerCode
        self.transactionDate = transactionDate
        self.expirationDate = expirationDate
        self.transactionRevocationDate = transactionRevocationDate
        self.promoOfferId = promoOfferId
        self.environment = environment
        self.ownershipType = ownershipType
        self.type = type
    }

    init?(coder: NSCoder) {
        originalTransactionId = coder.decodeObject(forKey: "originalTransactionId") as? String
        transactionId = coder.decodeObject(forKey: "transactionId") as? String
        offerCode = coder.decodeObject(forKey: "offerCode") as? String
        transactionDate = coder.decodeObject(forKey: "transactionDate") as? Date
        expirationDate = coder.decodeObject(forKey: "expirationDate") as? Date
        transactionRevocationDate = coder.decodeObject(forKey: "transactionRevocationDate") as? Date
        promoOfferId = coder.decodeObject(forKey: "promoOfferId") as? String
        environment = coder.decodeInteger(forKey: "environment")
        ownershipType = coder.decodeInteger(forKey: "ownershipType")
        type = coder.decodeInteger(forKey: "type")
    }

    func encode(with coder: NSCoder) {
        coder.encode(originalTransactionId, forKey: "originalTransactionId")
        coder.encode(transactionId, forKey: "transactionId")
        coder.encode(offerCode, forKey: "offerCode")
        coder.encode(transactionDate, forKey: "transactionDate")
        coder.encode(expirationDate, forKey: "expirationDate")
        coder.encode(transactionRevocationDate, forKey: "transactionRevocationDate")
        coder.encode(promoOfferId, forKey: "promoOfferId")
        coder.encode(environment, forKey: "environment")
        coder.encode(ownershipType, forKey: "ownershipType")
        coder.encode(type, forKey: "type")
    }

    func storeTransaction() -> Qonversion.Entitlement.StoreTransaction {
        return Qonversion.Entitlement.StoreTransaction(
            transactionId: transactionId,
            originalTransactionId: originalTransactionId,
            offerCode: offerCode,
            promoOfferId: promoOfferId,
            transactionDate: transactionDate,
            expirationDate: expirationDate,
            revocationDate: transactionRevocationDate,
            environment: environment == 0 ? .sandbox : .production,
            ownershipType: ownershipType == 1 ? .familyShared : .owner,
            type: Self.transactionType(from: type)
        )
    }

    /// QONTransactionType: unknown 0, subscriptionStarted 1,
    /// subscriptionRenewed 2, trialStarted 3, introStarted 4, introRenewed 5,
    /// nonConsumablePurchase 6.
    static func transactionType(from raw: Int) -> Qonversion.Entitlement.StoreTransaction.TransactionType {
        switch raw {
        case 1:
            return .subscriptionStarted
        case 2:
            return .subscriptionRenewed
        case 3:
            return .trialStarted
        case 4:
            return .introStarted
        case 5:
            return .introRenewed
        case 6:
            return .nonConsumablePurchase
        default:
            return .unknown
        }
    }
}
