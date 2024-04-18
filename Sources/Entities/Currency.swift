//
//  Currency.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 17.04.2024.
//

import Foundation

extension Qonversion {
    
    /// Currency details.
    /// Apple [Currency](https://developer.apple.com/documentation/foundation/decimal/formatstyle/currency) wrapper that is supported by all iOS versions, not only 16.0+ as original Apple Currency struct.
    public struct Currency {
        
        /// Currency identifier.
        public let identifier: String
        
        /// Currency symbol.
        public let symbol: String?
        
        init?(identifier: String?, symbol: String?) {
            guard let identifier = identifier else { return nil }
            
            self.identifier = identifier
            self.symbol = symbol
        }
        
    }
    
}
