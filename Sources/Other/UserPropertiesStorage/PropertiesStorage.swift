//
//  PropertiesStorage.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 26.02.2024.
//

import Foundation

protocol PropertiesStorage {

    func save(_ userProperty: Qonversion.UserProperty)

    func clear(properties: [Qonversion.UserProperty])

    func clear()

    func all() -> [Qonversion.UserProperty]
}
