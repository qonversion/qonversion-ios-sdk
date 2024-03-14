//
//  Qonversion.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

public struct Configuration {
    let apiKey: String
    let userDefaults: UserDefaults?
    
    public init(apiKey: String, userDefaults: UserDefaults?) {
        self.apiKey = apiKey
        self.userDefaults = userDefaults
    }
}

public final class Qonversion {
    public static let shared = Qonversion()
    
    private var userPropertiesManager: UserPropertiesManagerInterface?
    private var qonversionAssembly: QonversionAssembly?
    
    private init() { }
    
    public static func initialize(with configuration: Configuration) {
        let assembly: QonversionAssembly = QonversionAssembly(apiKey: configuration.apiKey, userDefaults: configuration.userDefaults)
        Qonversion.shared.qonversionAssembly = assembly
        Qonversion.shared.userPropertiesManager = assembly.userPropertiesManager()
    }
}
