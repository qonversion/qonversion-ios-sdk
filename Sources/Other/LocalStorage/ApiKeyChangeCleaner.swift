//
//  ApiKeyChangeCleaner.swift
//  Qonversion
//

import Foundation

/// Drops the previous project's cached state when the SDK is initialized with
/// a different project key.
struct ApiKeyChangeCleaner {

    private let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper

    init(localStorage: LocalStorageInterface, logger: LoggerWrapper) {
        self.localStorage = localStorage
        self.logger = logger
    }

    @discardableResult
    func run(apiKey: String) -> Bool {
        // No stored key means a fresh install OR an install upgrading from the
        // Objective-C SDK, which never wrote one — neither may be wiped.
        guard let storedApiKey: String = localStorage.string(forKey: SDKStorageKeys.apiKey) else {
            localStorage.set(string: apiKey, forKey: SDKStorageKeys.apiKey)
            return false
        }
        guard storedApiKey != apiKey else { return false }

        for key in SDKStorageKeys.unscoped {
            localStorage.removeObject(forKey: key)
        }
        // Per-key by construction, so they could be left behind — but nothing
        // will ever read the previous project's copies again.
        localStorage.removeObject(forKey: SDKStorageKeys.products(forApiKey: storedApiKey))
        localStorage.removeObject(forKey: SDKStorageKeys.requests(forApiKey: storedApiKey))

        localStorage.set(string: apiKey, forKey: SDKStorageKeys.apiKey)
        logger.info("The project key changed — the previous project's cached data was dropped.")

        return true
    }
}
