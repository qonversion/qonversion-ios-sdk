//
//  UserPropertiesStorage.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 26.02.2024.
//

import Foundation

final class UserPropertiesStorage: PropertiesStorage {

    // Mutated from the caller's thread (setProperty) and from the sending
    // task concurrently.
    private let lock = NSLock()
    private var userProperties: [Qonversion.UserProperty] = []

    func save(_ userProperty: Qonversion.UserProperty) {
        lock.lock()
        defer { lock.unlock() }
        userProperties.append(userProperty)
    }

    func clear(properties: [Qonversion.UserProperty]) {
        lock.lock()
        defer { lock.unlock() }
        userProperties.removeAll(where: { properties.contains($0) })
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        userProperties = []
    }

    func all() -> [Qonversion.UserProperty] {
        lock.lock()
        defer { lock.unlock() }
        return Array(userProperties)
    }
}
