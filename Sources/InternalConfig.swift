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

    init(userId: String, launchMode: Qonversion.LaunchMode = .analytics) {
        self.userId = userId
        self.launchMode = launchMode
    }
    
    func getUserId() -> String {
        return userId
    }
}
