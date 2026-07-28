//
//  InternalConfig.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 27.02.2024.
//

import Foundation

protocol UserIdProvider {
    func getUserId() -> String
}

protocol LaunchModeProvider {
    var launchMode: Qonversion.LaunchMode { get }
}

// @unchecked: userId is lock-guarded, the rest is set once at init.
final class InternalConfig: UserIdProvider, LaunchModeProvider, @unchecked Sendable {

    // Written by the user gate (logout/identity switch) and read by every
    // request-building path concurrently.
    private let lock = NSLock()
    private var _userId: String

    var userId: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _userId
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _userId = newValue
        }
    }

    var launchMode: Qonversion.LaunchMode
    var entitlementsCacheLifetime: Qonversion.EntitlementsCacheLifetime
    var logLevel: Qonversion.LogLevel

    init(userId: String, launchMode: Qonversion.LaunchMode = .analytics, entitlementsCacheLifetime: Qonversion.EntitlementsCacheLifetime = .month, logLevel: Qonversion.LogLevel = .verbose) {
        self._userId = userId
        self.launchMode = launchMode
        self.entitlementsCacheLifetime = entitlementsCacheLifetime
        self.logLevel = logLevel
    }
    
    func getUserId() -> String {
        return userId
    }
}
