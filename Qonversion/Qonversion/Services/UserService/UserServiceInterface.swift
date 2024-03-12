//
//  UserServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

protocol UserServiceInterface {
    
    func user() async throws -> User
    
    func createUser() async throws -> User
    
    func userId() -> String
    
}
