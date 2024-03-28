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

final class InternalConfig: UserIdProvider {
    
    var userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    func getUserId() -> String {
        return userId
    }
}
