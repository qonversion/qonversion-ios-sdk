//
//  Configuration.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.03.2024.
//

import Foundation

public struct Configuration {
    let apiKey: String
    let launchMode: LaunchMode
    var userDefaults: UserDefaults? = nil
    
    public init(apiKey: String, launchMode: LaunchMode) {
        self.apiKey = apiKey
        self.launchMode = launchMode
    }
    
    mutating func setCustomUserDefaults(_ userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
}
