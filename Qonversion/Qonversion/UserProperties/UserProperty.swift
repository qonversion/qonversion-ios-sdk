//
//  UserProperty.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

struct UserProperty : Decodable {
    
    let key: String
    let value: String
    let definedKey: UserPropertyKey
    
    private enum CodingKeys: String, CodingKey {
        case key, value
    }
//    
//    init(key: String, value: String) {
//        self.key = key
//        self.value = value
//        definedKey = UserPropertyKey.from(key: key)
//    }
//    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        definedKey = UserPropertyKey.from(key: key)
    }
}
