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
/// It is consumed from the host-provided defaults too: the previous SDK wrote
/// every blob to both its suite and the host's `customUserDefaults`, so with an
/// app-group suite the dead queue would otherwise sit there forever.
struct LegacyPurchasesQueueMigration {

    private enum Constants: String {
        case suiteName = "qonversion.localstorage.main"
        case queueKey = "com.qonversion.keys.requests.stored.purchases"
    }

    private let legacyDefaults: UserDefaults?
    private let hostDefaults: UserDefaults?

    init(legacyDefaults: UserDefaults? = UserDefaults(suiteName: Constants.suiteName.rawValue), hostDefaults: UserDefaults? = nil) {
        self.legacyDefaults = legacyDefaults
        self.hostDefaults = hostDefaults
    }

    func run() {
        let sources: [UserDefaults] = [hostDefaults, legacyDefaults].compactMap { $0 }
        LegacyDefaults.remove(Constants.queueKey.rawValue, from: sources)
    }
}
