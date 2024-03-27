//
//  LocalStorageInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 11.03.2024.
//

protocol LocalStorageInterface {
    
    func object(forKey key: String) -> Any?

    func set(_ value: Any?, forKey key: String)
    
    func removeObject(forKey key: String)

    func string(forKey key: String) -> String?

    func array(forKey key: String) -> [Any]?

    func dictionary(forKey key: String) -> [String : Any]?

    func data(forKey key: String) -> Data?

    func integer(forKey key: String) -> Int

    func float(forKey key: String) -> Float

    func double(forKey key: String) -> Double

    func bool(forKey key: String) -> Bool

    func url(forKey key: String) -> URL?

    func set(integer: Int, forKey key: String)
    
    func set(float: Float, forKey key: String)

    func set(double: Double, forKey key: String)

    func set(bool: Bool, forKey key: String)
    
}
