//
//  UserPropertiesStorage.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 26.02.2024.
//

import Foundation

final class UserPropertiesStorage: PropertiesStorage {

    private var userProperties: [UserProperty] = []

    func save(_ userProperty: UserProperty) {
        userProperties.append(userProperty)
    }

    func clear(properties: [UserProperty]) {
        userProperties = userProperties.filter { userProperty in !properties.contains { $0 == userProperty } }
    }

    func clear() {
        userProperties = []
    }

    func all() -> [UserProperty] {
        return Array(userProperties)
    }
}
