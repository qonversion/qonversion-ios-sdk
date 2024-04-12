//
//  UserServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

protocol UserServiceInterface {
    
    func user() async throws -> Qonversion.User
    
    func createUser() async throws -> Qonversion.User
    
    func generateUserId() -> String
    
}
