//
//  LocalStorageInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 11.03.2024.
//

protocol LocalStorageInterface {
    
    func object(forKey defaultName: String) -> Any?

    func set(_ value: Any?, forKey defaultName: String)
    
    func removeObject(forKey defaultName: String)

    func string(forKey defaultName: String) -> String?

    func array(forKey defaultName: String) -> [Any]?

    func dictionary(forKey defaultName: String) -> [String : Any]?

    func data(forKey defaultName: String) -> Data?

    func integer(forKey defaultName: String) -> Int

    func float(forKey defaultName: String) -> Float

    func double(forKey defaultName: String) -> Double

    func bool(forKey defaultName: String) -> Bool

    func url(forKey defaultName: String) -> URL?

    func set(integer: Int, forKey defaultName: String)
    
    func set(float: Float, forKey defaultName: String)

    func set(double: Double, forKey defaultName: String)

    func set(bool: Bool, forKey defaultName: String)
    
}
