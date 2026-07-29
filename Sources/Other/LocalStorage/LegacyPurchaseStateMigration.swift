//
//  LegacyPurchaseStateMigration.swift
//  Qonversion
//

import Foundation

/// Carries the previous SDK generation's purchase bookkeeping into this one.
///
/// Two keys, both of which change what this SDK does on its very first launch
/// after an upgrade:
///
///   * `com.qonversion.keys.purchases.options` — an `NSKeyedArchiver` archive
///     of `NSDictionary<NSString *, QONPurchaseOptions *>`, keyed by store
///     product id. That SDK removed an entry only after the purchase report
///     SUCCEEDED, so anything still there belongs to a transaction it never
///     finished — exactly the transactions this SDK's unfinished sweep
///     re-reports on this launch. Without the contextKeys and screenUid, they
///     are re-reported with no paywall attribution at all, and the revenue
///     silently detaches from the experiment that produced it.
///   * `isHistoricalDataSynced` — a plain bool. Hosts are documented to call
///     `syncHistoricalData()` on every start; that flag is what made the call a
///     no-op after the first success. Losing it re-sends the user's entire
///     purchase history to the backend once more.
///
/// Nothing this SDK has already written is overwritten, and the legacy keys are
/// consumed either way: undecodable data must not be retried on every launch
/// forever.
struct LegacyPurchaseStateMigration {

    /// What the run actually managed to carry over. Returned (and logged) so
    /// the outcome is observable rather than guessed at.
    struct Outcome: Equatable {
        var migratedAssociations: Int = 0
        var migratedHistoricalFlag: Bool = false
        var optionsDecodeFailed: Bool = false
    }

    private enum LegacyKeys: String {
        case suiteName = "qonversion.localstorage.main"
        case purchaseOptions = "com.qonversion.keys.purchases.options"
        case historicalDataSynced = "isHistoricalDataSynced"
    }

    /// Owned by PurchaseAssociationsStorage and PurchasesManager; repeated here
    /// because they are file-private there. Changing one without the other
    /// breaks the migration silently, so both sides carry this note.
    private enum TargetKeys: String {
        case purchaseAssociations = "qonversion.keys.purchaseAssociations"
        case historicalDataSynced = "qonversion.keys.historicalDataSynced"
    }

    private let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper
    private let legacyDefaults: UserDefaults?
    private let hostDefaults: UserDefaults?

    init(
        localStorage: LocalStorageInterface,
        logger: LoggerWrapper,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: LegacyPurchaseStateMigration.legacySuiteName),
        hostDefaults: UserDefaults? = nil
    ) {
        self.localStorage = localStorage
        self.logger = logger
        self.legacyDefaults = legacyDefaults
        self.hostDefaults = hostDefaults
    }

    static var legacySuiteName: String { LegacyKeys.suiteName.rawValue }

    @discardableResult
    func run() -> Outcome {
        var outcome = Outcome()
        migratePurchaseOptions(into: &outcome)
        migrateHistoricalDataFlag(into: &outcome)

        LegacyDefaults.remove(LegacyKeys.purchaseOptions.rawValue, from: sources)
        LegacyDefaults.remove(LegacyKeys.historicalDataSynced.rawValue, from: sources)

        if outcome != Outcome() {
            logger.info("Migrated the previous SDK generation's purchase state: \(outcome.migratedAssociations) purchase contexts, historical sync flag \(outcome.migratedHistoricalFlag ? "carried over" : "absent").")
        }

        return outcome
    }

    // MARK: - Private

    /// The host-provided defaults first, mirroring `QNUserDefaultsStorage`,
    /// which wrote every blob to both and read the custom one first.
    private var sources: [UserDefaults] {
        return [hostDefaults, legacyDefaults].compactMap { $0 }
    }

    private func migratePurchaseOptions(into outcome: inout Outcome) {
        guard let data: Data = LegacyDefaults.data(forKey: LegacyKeys.purchaseOptions.rawValue, in: sources) else { return }

        let mappings: [String: AnyClass] = ["QONPurchaseOptions": LegacyArchivedPurchaseOptions.self]
        guard let root = LegacyDefaults.unarchivedRoot(from: data, classMappings: mappings),
              let archived = root as? [String: LegacyArchivedPurchaseOptions] else {
            outcome.optionsDecodeFailed = true
            return
        }

        var associations: [String: PurchaseAssociations] = (try? localStorage.object(forKey: TargetKeys.purchaseAssociations.rawValue, dataType: [String: PurchaseAssociations].self)) ?? [:]
        var migrated = 0
        for (storeProductId, options) in archived {
            // Never over an answer this SDK already has.
            guard associations[storeProductId] == nil else { continue }
            guard let association: PurchaseAssociations = options.associations() else { continue }

            associations[storeProductId] = association
            migrated += 1
        }
        guard migrated > 0 else { return }

        do {
            try localStorage.set(associations, forKey: TargetKeys.purchaseAssociations.rawValue)
            outcome.migratedAssociations = migrated
        } catch {
            logger.warning("Failed to store the migrated purchase contexts: " + error.message)
        }
    }

    private func migrateHistoricalDataFlag(into outcome: inout Outcome) {
        guard !localStorage.bool(forKey: TargetKeys.historicalDataSynced.rawValue) else { return }
        guard LegacyDefaults.bool(forKey: LegacyKeys.historicalDataSynced.rawValue, in: sources) else { return }

        localStorage.set(bool: true, forKey: TargetKeys.historicalDataSynced.rawValue)
        outcome.migratedHistoricalFlag = true
    }
}

// MARK: - Archived shapes

/// Key-compatible stand-in for the Objective-C `QONPurchaseOptions`: the archive
/// keys are the property names, so decoding through this reads the real
/// payload. Only ever used for reading (and, in tests, for writing fixtures in
/// the genuine legacy format).
final class LegacyArchivedPurchaseOptions: NSObject, NSCoding {

    let quantity: Int
    let contextKeys: [String]?
    let screenUid: String?

    init(quantity: Int, contextKeys: [String]?, screenUid: String?) {
        self.quantity = quantity
        self.contextKeys = contextKeys
        self.screenUid = screenUid
    }

    init?(coder: NSCoder) {
        quantity = coder.decodeInteger(forKey: "quantity")
        contextKeys = coder.decodeObject(forKey: "contextKeys") as? [String]
        screenUid = coder.decodeObject(forKey: "screenUid") as? String
    }

    func encode(with coder: NSCoder) {
        coder.encode(quantity, forKey: "quantity")
        coder.encode(contextKeys, forKey: "contextKeys")
        coder.encode(screenUid, forKey: "screenUid")
    }

    /// nil when the entry carries no association at all — quantity and promo
    /// offer are store-affecting options that the report does not take, so an
    /// entry without context or screen is nothing to migrate.
    func associations() -> PurchaseAssociations? {
        let keys: [String]? = (contextKeys?.isEmpty == false) ? contextKeys : nil
        guard keys != nil || screenUid != nil else { return nil }

        return PurchaseAssociations(contextKeys: keys, screenUid: screenUid)
    }
}

// MARK: - Shared legacy reads

/// The Objective-C SDK wrote every blob to BOTH its own suite and the
/// host-provided `customUserDefaults`, and read the custom one first. Every
/// migration therefore has to look in, and clean, both.
enum LegacyDefaults {

    static func data(forKey key: String, in sources: [UserDefaults]) -> Data? {
        for source in sources {
            if let data: Data = source.data(forKey: key) {
                return data
            }
        }

        return nil
    }

    static func double(forKey key: String, in sources: [UserDefaults]) -> Double {
        for source in sources {
            let value: Double = source.double(forKey: key)
            if value != 0 {
                return value
            }
        }

        return 0
    }

    static func bool(forKey key: String, in sources: [UserDefaults]) -> Bool {
        return sources.contains { $0.bool(forKey: key) }
    }

    static func remove(_ key: String, from sources: [UserDefaults]) {
        for source in sources {
            source.removeObject(forKey: key)
        }
    }

    /// `NSKeyedArchiver.archivedDataWithRootObject:` (which is what wrote these
    /// payloads) is the non-secure form, so secure coding has to be off and the
    /// root read by key.
    static func unarchivedRoot(from data: Data, classMappings: [String: AnyClass]) -> Any? {
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
