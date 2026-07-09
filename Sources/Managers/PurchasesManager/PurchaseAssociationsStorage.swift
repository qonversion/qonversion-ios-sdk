//
//  PurchaseAssociationsStorage.swift
//  Qonversion
//

import Foundation

/// The association part of purchase options (contextKeys, screenUid), keyed
/// by store product id and persisted for the whole purchase lifecycle: a
/// report that happens after a relaunch (unfinished sweep, Ask to Buy
/// approval via the listener) must still carry the paywall context of the
/// original purchase call. Mirrors the production SDK behavior.
struct PurchaseAssociations: Codable {

    let contextKeys: [String]?
    let screenUid: String?
}

// @unchecked: lock-guarded.
final class PurchaseAssociationsStorage: @unchecked Sendable {

    private enum Constants: String {
        case storageKey = "qonversion.keys.purchaseAssociations"
    }

    private let lock = NSLock()
    private let localStorage: LocalStorageInterface

    init(localStorage: LocalStorageInterface) {
        self.localStorage = localStorage
    }

    func store(_ associations: PurchaseAssociations, for storeProductId: String) {
        lock.lock()
        defer { lock.unlock() }

        var all = load()
        all[storeProductId] = associations
        persist(all)
    }

    func associations(for storeProductId: String) -> PurchaseAssociations? {
        lock.lock()
        defer { lock.unlock() }

        return load()[storeProductId]
    }

    func remove(for storeProductId: String) {
        lock.lock()
        defer { lock.unlock() }

        var all = load()
        guard all.removeValue(forKey: storeProductId) != nil else { return }
        persist(all)
    }

    private func load() -> [String: PurchaseAssociations] {
        (try? localStorage.object(forKey: Constants.storageKey.rawValue, dataType: [String: PurchaseAssociations].self)) ?? [:]
    }

    private func persist(_ all: [String: PurchaseAssociations]) {
        try? localStorage.set(all, forKey: Constants.storageKey.rawValue)
    }
}
