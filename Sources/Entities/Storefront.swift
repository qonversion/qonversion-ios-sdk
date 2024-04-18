//
//  Storefront.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 17.04.2024.
//

import Foundation

extension Qonversion {
    
    /// App Store [Storefront](https://developer.apple.com/documentation/storekit/storefront) wrapper.
    public struct Storefront {
        
        /// The three-letter code representing the country or region associated with the App Store storefront.
        public let countryCode: String

        /// A value defined by Apple that uniquely identifies an App Store storefront.
        public let id: String?
        
        init?(countryCode: String?, id: String?) {
            guard let countryCode: String = countryCode else { return nil }
            
            self.countryCode = countryCode
            self.id = id
        }
    }
    
}
