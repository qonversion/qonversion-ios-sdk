//
//  LegacyPurchasesQueueMigration.swift
//  Qonversion
//

import Foundation

/// Consumes the offline purchase queue left by the previous SDK generation.
///
/// That queue is an NSKeyedArchiver-encoded dictionary of transaction id →
/// NSURLRequest, stored in the SDK's own UserDefaults suite. The requests
/// target the previous API — different endpoint, auth and body shape — so
/// they cannot be replayed against v4, and the transaction ids alone are not
/// enough to rebuild them (the v4 purchase report needs the signed store
/// payload). The purchases behind them are not lost: that SDK never finished a
/// transaction whose report had failed, so the unfinished-transaction sweep
/// re-reports them in v4 form on the first launch.
///
/// The key is therefore consumed, not migrated, so it stops occupying storage.
struct LegacyPurchasesQueueMigration {

    private enum Constants: String {
        case suiteName = "qonversion.localstorage.main"
        case queueKey = "com.qonversion.keys.requests.stored.purchases"
    }

    private let legacyDefaults: UserDefaults?

    init(legacyDefaults: UserDefaults? = UserDefaults(suiteName: Constants.suiteName.rawValue)) {
        self.legacyDefaults = legacyDefaults
    }

    func run() {
        legacyDefaults?.removeObject(forKey: Constants.queueKey.rawValue)
    }
}
