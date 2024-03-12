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
    
    func object(forKey defaultName: String) -> Any? {
        return self.userDefaults.object(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        userDefaults.set(value, forKey: defaultName)
    }
    
    func removeObject(forKey defaultName: String) {
        userDefaults.removeObject(forKey: defaultName)
    }

    func string(forKey defaultName: String) -> String? {
        userDefaults.string(forKey: defaultName)
    }

    func array(forKey defaultName: String) -> [Any]? {
        return userDefaults.array(forKey: defaultName)
    }

    func dictionary(forKey defaultName: String) -> [String : Any]? {
        return userDefaults.dictionary(forKey: defaultName)
    }

    func data(forKey defaultName: String) -> Data? {
        return userDefaults.data(forKey: defaultName)
    }

    func integer(forKey defaultName: String) -> Int {
        return userDefaults.integer(forKey: defaultName)
    }

    func float(forKey defaultName: String) -> Float {
        return userDefaults.float(forKey: defaultName)
    }

    func double(forKey defaultName: String) -> Double {
        return userDefaults.double(forKey: defaultName)
    }

    func bool(forKey defaultName: String) -> Bool {
        return userDefaults.bool(forKey: defaultName)
    }

    func url(forKey defaultName: String) -> URL? {
        return userDefaults.url(forKey: defaultName)
    }

    func set(integer: Int, forKey defaultName: String) {
        userDefaults.set(integer, forKey: defaultName)
    }

    
    func set(float: Float, forKey defaultName: String) {
        userDefaults.set(float, forKey: defaultName)
    }

    func set(double: Double, forKey defaultName: String) {
        userDefaults.set(double, forKey: defaultName)
    }

    func set(bool: Bool, forKey defaultName: String) {
        userDefaults.set(bool, forKey: defaultName)
    }
    
}
