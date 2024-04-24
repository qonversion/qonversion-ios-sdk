//
//  Offerings.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.04.2024.
//

import Foundation

extension Qonversion {
    
    /// Offerings list wrapper
    public struct Offerings {
        
        /// Available offerings list.
        let availableOfferings: [Qonversion.Offering]
        
        /// Offering with tag `main` set via Qonversion Dashboard.
        let main: Qonversion.Offering?
        
        init(offerings: [Qonversion.Offering]) {
            self.availableOfferings = offerings
            self.main = offerings.first { $0.tag == .main }
        }
        
    }

    /// Offering from Qonversion Dashboard that contains a batch of Qonversion products.
    public struct Offering: Decodable {
        
        /// Offering tag enum
        enum Tag: String, Decodable {
            
            /// Main tag
            case main
            
            /// Case for an offering without any tag
            case none
            
        }
        
        
        /// Offering identifier
        let id: String
        
        /// Offering tag
        let tag: Qonversion.Offering.Tag
        
        /// List of the products for the current offering
        let products: [Qonversion.Product]
        
    }
    
}
