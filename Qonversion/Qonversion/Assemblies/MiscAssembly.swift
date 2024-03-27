//
//  MiscAssembly.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.03.2024.
//

import Foundation

final class MiscAssembly {
    
    func delayCalculator() -> IncrementalDelayCalculator {
        return IncrementalDelayCalculator()
    }
    
    func userPropertiesStorage() -> UserPropertiesStorage {
        return UserPropertiesStorage()
    }
    
}
