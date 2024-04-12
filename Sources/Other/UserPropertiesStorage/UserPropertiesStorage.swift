//
//  UserPropertiesStorage.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 26.02.2024.
//

import Foundation

final class UserPropertiesStorage: PropertiesStorage {

    private var userProperties: [Qonversion.UserProperty] = []

    func save(_ userProperty: Qonversion.UserProperty) {
        userProperties.append(userProperty)
    }

    func clear(properties: [Qonversion.UserProperty]) {
        userProperties.removeAll(where: { properties.contains($0) })
    }

    func clear() {
        userProperties = []
    }

    func all() -> [Qonversion.UserProperty] {
        return Array(userProperties)
    }
}
