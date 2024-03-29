//
//  UserProperty.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

public struct UserProperty : Decodable, Encodable, Equatable, Hashable {

    let key: String
    let value: String
    var definedKey: UserPropertyKey { UserPropertyKey(rawValue: key) ?? .custom }
}
