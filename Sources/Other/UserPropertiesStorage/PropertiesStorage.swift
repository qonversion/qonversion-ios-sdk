//
//  PropertiesStorage.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 26.02.2024.
//

import Foundation

protocol PropertiesStorage {

    func save(_ userProperty: UserProperty)

    func clear(properties: [UserProperty])

    func clear()

    func all() -> [UserProperty]
}
