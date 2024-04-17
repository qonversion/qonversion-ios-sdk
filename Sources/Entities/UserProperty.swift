//
//  UserProperty.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

extension Qonversion {
    
    /// User property info
    public struct UserProperty : Decodable, Encodable, Equatable, Hashable {
        
        /// Raw property key
        public let key: String
        
        /// Property value
        public let value: String
        
        /// Qonversion defined property key. ``Qonversion/Qonversion/UserPropertyKey`` for non-Qonversion properties.
        public var definedKey: UserPropertyKey { UserPropertyKey(rawValue: key) ?? .custom }
        
    }
    
}
