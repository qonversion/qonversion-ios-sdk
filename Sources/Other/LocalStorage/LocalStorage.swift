//
//  LocalStorage.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 11.03.2024.
//

import Foundation

final class LocalStorage: LocalStorageInterface {
    
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    init(userDefaults: UserDefaults, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }
    
    func object<T>(forKey key: String, dataType: T.Type) throws -> T? where T : Decodable {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        
        do {
            let result: T = try decoder.decode(dataType, from: data)

            return result
        } catch {
            throw QonversionError(type: .storageDeserializationFailed, error: error)
        }
    }

    func set(_ value: Encodable?, forKey key: String) throws {
        guard let value else {
            return userDefaults.set(value, forKey: key)
        }

        var data: Data? = nil
        do {
            data = try encoder.encode(value)
        } catch {
            throw QonversionError(type: QonversionErrorType.storageSerializationFailed, error: error)
        }
        userDefaults.set(data, forKey: key)
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
    
    func set(string: String, forKey key: String) {
        userDefaults.set(string, forKey: key)
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
