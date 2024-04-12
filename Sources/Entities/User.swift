//
//  User.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

extension Qonversion {
    
    struct User: Decodable {
        
        enum Environment: String, Decodable {
            case sandbox
            case production
        }
        
        private enum CodingKeys: String, CodingKey {
            case id
            case creationDate = "created"
            case environment
        }
        
        let id: String
        let creationDate: Date
        let environment: User.Environment
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            creationDate = try container.decode(Date.self, forKey: .creationDate)
            environment = try container.decode(User.Environment.self, forKey: .environment)
            id = try container.decode(String.self, forKey: .id)
        }
        
    }
    
}