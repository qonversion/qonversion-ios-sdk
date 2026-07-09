//
//  User.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

extension Qonversion {
    
    public struct User: Codable, Sendable {
        
        enum Environment: String, Codable, Sendable {
            case production = "prod"
            case sandbox
        }
        
        private enum CodingKeys: String, CodingKey {
            case id
            case creationDate = "created_at"
            case identityId = "identity_id"
            case environment
        }
        
        /// Qonversion User ID
        public let id: String
        
        /// Date when the user was created
        public let creationDate: Date?

        /// The integrator's identity linked to the user, if any
        public let identityId: String?
        
        let environment: User.Environment

        init(id: String, creationDate: Date? = nil, identityId: String? = nil, environment: User.Environment = .production) {
            self.id = id
            self.creationDate = creationDate
            self.identityId = identityId
            self.environment = environment
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
            identityId = try container.decodeIfPresent(String.self, forKey: .identityId)
            // Tolerant: an unknown environment value must not fail the decode.
            let rawEnvironment = try container.decodeIfPresent(String.self, forKey: .environment)
            environment = rawEnvironment.flatMap { User.Environment(rawValue: $0) } ?? .production
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(creationDate, forKey: .creationDate)
            try container.encodeIfPresent(identityId, forKey: .identityId)
            try container.encode(environment, forKey: .environment)
        }
    }
}
