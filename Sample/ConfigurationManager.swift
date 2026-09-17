//
//  ConfigurationManager.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

/// Where the sample points itself. Both values are read once at launch, so a
/// change only takes effect after a restart — see HomeView's hidden dialog
/// (tap the logo five times).
///
/// Keeping them in UserDefaults rather than in source is what lets the same
/// build be aimed at production, at staging or at a local stack without
/// editing a file that would then have to be kept out of a commit.
enum ConfigurationManager {

    private static let projectKeyKey = "project_key"
    private static let apiUrlKey = "api_url"

    // TEMPORARY — REVERT BEFORE RELEASE.
    //
    // Pointed at the LOCAL dev stack. The /v4 SDK surface exists nowhere else
    // that works end to end: it is not on main (so production answers every
    // v4 call from the not-found handler), and on the feat/v4-sdk-support
    // staging environment POST /v4/users times out — userman reads there, but
    // its MySQL writes hang.
    //
    // Production values to restore:
    //   defaultProjectKey = "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2"
    //   defaultApiUrl     = nil
    static let defaultProjectKey = "dev_access_token_789"

    /// The Mac's LAN address rather than localhost, so a device on the same
    /// Wi-Fi reaches it; the simulator is fine with it too. Plain HTTP is what
    /// the local gateway serves.
    ///
    /// Staging, for when its write path is fixed:
    ///   key "8aa76234e3cac3f4dee02a7aace44e335e2e8f08da293dcdab897ac2d7da387e"
    ///   url "http://feat-v4-sdk-support.api-gateway.stage.qmoons.me"
    static let defaultApiUrl: String? = "http://192.168.1.75:7101"

    private static var userDefaults: UserDefaults { .standard }

    static func getProjectKey() -> String {
        guard let stored: String = userDefaults.string(forKey: projectKeyKey), !stored.isEmpty else {
            return defaultProjectKey
        }

        return stored
    }

    /// The configured endpoint, or the default one. A value stored through the
    /// dialog always wins, so the default can be overridden without a rebuild.
    static func getApiUrl() -> String? {
        guard let stored: String = userDefaults.string(forKey: apiUrlKey), !stored.isEmpty else {
            return defaultApiUrl
        }

        return stored
    }

    /// Only what the dialog stored, with no default substituted — the dialog
    /// needs to know whether an override exists, not which endpoint is in use.
    static func storedApiUrl() -> String? {
        guard let stored: String = userDefaults.string(forKey: apiUrlKey), !stored.isEmpty else {
            return nil
        }

        return stored
    }

    static func storeConfiguration(projectKey: String, apiUrl: String?) {
        if projectKey.isEmpty {
            userDefaults.removeObject(forKey: projectKeyKey)
        } else {
            userDefaults.set(projectKey, forKey: projectKeyKey)
        }

        if let apiUrl: String = apiUrl, !apiUrl.isEmpty {
            userDefaults.set(apiUrl, forKey: apiUrlKey)
        } else {
            userDefaults.removeObject(forKey: apiUrlKey)
        }
    }

    static func resetConfiguration() {
        userDefaults.removeObject(forKey: projectKeyKey)
        userDefaults.removeObject(forKey: apiUrlKey)
    }

    static var hasCustomConfiguration: Bool {
        return getApiUrl() != nil || userDefaults.string(forKey: projectKeyKey)?.isEmpty == false
    }
}
