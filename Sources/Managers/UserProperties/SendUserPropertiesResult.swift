//
//  SendUserPropertiesResult.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 27.02.2024.
//

import Foundation

struct SendUserPropertiesResult: Decodable {
    
    let savedProperties: [Qonversion.UserProperty]
    let propertyErrors: [UserPropertyError]
    
    struct UserPropertyError: Decodable {
        let key: String
        let error: String
    }
}
