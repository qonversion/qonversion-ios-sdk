//
//  LocalStorage.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 11.03.2024.
//

import Foundation

final class LocalStorage: LocalStorageInterface {
    
    let userDefaults: UserDefaults
    
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    func object(forKey key: String) -> Any? {
        return self.userDefaults.object(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    func array(forKey key: String) -> [Any]? {
        return userDefaults.array(forKey: key)
    }

    func dictionary(forKey key: String) -> [String : Any]? {
        return userDefaults.dictionary(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        return userDefaults.data(forKey: key)
    }

    func integer(forKey key: String) -> Int {
        return userDefaults.integer(forKey: key)
    }

    func float(forKey key: String) -> Float {
        return userDefaults.float(forKey: key)
    }

    func double(forKey key: String) -> Double {
        return userDefaults.double(forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        return userDefaults.bool(forKey: key)
    }

    func url(forKey key: String) -> URL? {
        return userDefaults.url(forKey: key)
    }

    func set(integer: Int, forKey key: String) {
        userDefaults.set(integer, forKey: key)
    }

    func set(float: Float, forKey key: String) {
        userDefaults.set(float, forKey: key)
    }

    func set(double: Double, forKey key: String) {
        userDefaults.set(double, forKey: key)
    }

    func set(bool: Bool, forKey key: String) {
        userDefaults.set(bool, forKey: key)
    }
}
