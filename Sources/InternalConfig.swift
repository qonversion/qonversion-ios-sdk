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

final class InternalConfig: UserIdProvider, LaunchModeProvider {
    
    var userId: String
    var launchMode: Qonversion.LaunchMode
    var entitlementsCacheLifetime: Qonversion.EntitlementsCacheLifetime
    var logLevel: Qonversion.LogLevel

    init(userId: String, launchMode: Qonversion.LaunchMode = .analytics, entitlementsCacheLifetime: Qonversion.EntitlementsCacheLifetime = .month, logLevel: Qonversion.LogLevel = .verbose) {
        self.userId = userId
        self.launchMode = launchMode
        self.entitlementsCacheLifetime = entitlementsCacheLifetime
        self.logLevel = logLevel
    }
    
    func getUserId() -> String {
        return userId
    }
}
