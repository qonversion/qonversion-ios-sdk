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
    // Pointed at the api-gateway PR environment of feat/v4-sdk-support, which
    // is the only place the /v4 SDK surface is deployed: it does not exist on
    // main, so production answers every v4 call from the not-found handler.
    // That environment is torn down when the PR merges.
    //
    // Production values to restore:
    //   defaultProjectKey = "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2"
    //   defaultApiUrl     = nil
    static let defaultProjectKey = "8aa76234e3cac3f4dee02a7aace44e335e2e8f08da293dcdab897ac2d7da387e"

    /// Plain HTTP on purpose: the staging ingress serves the Kubernetes
    /// "Fake Certificate", which iOS refuses outright — and no ATS exception
    /// waives certificate validation, only the requirement to use TLS.
    static let defaultApiUrl: String? = "http://feat-v4-sdk-support.api-gateway.stage.qmoons.me"

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
