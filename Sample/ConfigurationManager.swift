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

    static let defaultProjectKey = "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2"

    private static var userDefaults: UserDefaults { .standard }

    static func getProjectKey() -> String {
        guard let stored: String = userDefaults.string(forKey: projectKeyKey), !stored.isEmpty else {
            return defaultProjectKey
        }

        return stored
    }

    /// nil means production — the SDK's own default host.
    static func getApiUrl() -> String? {
        return userDefaults.string(forKey: apiUrlKey)
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
