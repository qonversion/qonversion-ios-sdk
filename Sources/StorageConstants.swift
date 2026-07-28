//
//  StorageConstants.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.02.2024.
//

enum StorageConstants: String {
    case prefix = "storage.qonversion.io."
    case unprocessedRequests
}

/// Every key this SDK persists into the host-configured UserDefaults suite.
/// The owning types keep their own file-private copies of these strings —
/// both sides have to move together, or a project switch silently stops
/// dropping a cache.
enum SDKStorageKeys {

    // Written regardless of the project key, which is what makes a project
    // switch undetectable without an explicit stored key to compare against.
    static let unscoped: [String] = [
        "qonversion.keys.entitlements",
        "qonversion.keys.entitlementsTimestamp",
        "qonversion.keys.entitlementsBackendTimestamp",
        "qonversion.keys.productsPermissions",
        "qonversion.keys.user",
        "qonversion.keys.identityExternalId",
        "qonversion.keys.userId",
        "qonversion.keys.originalUserId",
        "qonversion.keys.purchaseAssociations",
        "qonversion.keys.surfacedTransactions",
        "qonversion.keys.historicalDataSynced",
        "qonversion.keys.crashReports",
        InternalConstants.storagePrefix.rawValue + "device"
    ]

    // The project key this install last ran with.
    static var apiKey: String { "qonversion.keys.apiKey" }

    static func products(forApiKey apiKey: String) -> String {
        return "qonversion.keys.products." + apiKey
    }

    static func requests(forApiKey apiKey: String) -> String {
        return InternalConstants.storagePrefix.rawValue + "requests." + apiKey
    }
}
