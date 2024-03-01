//
//  UserProperty.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

struct UserProperty : Decodable, Encodable, Equatable {
    
    let key: String
    let value: String
    let definedKey: UserPropertyKey

    private enum CodingKeys: String, CodingKey {
        case key, value
    }

    init(key: String, value: String) {
        self.key = key
        self.value = value
        definedKey = UserPropertyKey(rawValue: key) ?? .custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        let value = try container.decode(String.self, forKey: .value)
        self.init(key: key, value: value)
    }
}
