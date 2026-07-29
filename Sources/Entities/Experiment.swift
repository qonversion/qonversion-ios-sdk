//
//  Experiment.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    /// Experiment, created via Qonversion Dashboard
    public struct Experiment: Decodable, Sendable {
        
        /// Information about the experiment group
        public struct Group: Decodable, Sendable {

            /// Possible types of the experiment group
            public enum GroupType: String, Decodable, Sendable {
                
                /// Unknown experiment group type
                case unknown
                
                /// Control experiment group
                case control
                
                /// Tratment experiment group
                case treatment
            }

            /// Experiment group name
            public let name: String

            /// Experiment group identifier
            public let identifier: String

            /// Experiment group type
            public let type: GroupType

            init(name: String, identifier: String, type: GroupType) {
                self.name = name
                self.identifier = identifier
                self.type = type
            }

            init() {
                self.name = ""
                self.identifier = ""
                self.type = .unknown
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // None of the known keys means a schema break, not an
                // incomplete group.
                guard !container.allKeys.isEmpty else {
                    let context = DecodingError.Context(codingPath: container.codingPath, debugDescription: "Experiment group carries none of the expected keys")
                    throw DecodingError.dataCorrupted(context)
                }

                // A missing key used to fail the group, and a failed group took
                // the whole remote config — payload included — with it.
                name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
                identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
                // Unknown backend values must not fail the whole config decode.
                let typeStr: String? = try container.decodeIfPresent(String.self, forKey: .type)
                type = typeStr.flatMap { GroupType(rawValue: $0) } ?? .unknown
            }

            private enum CodingKeys: String, CodingKey {
                case name
                // The backend names every entity identifier "uid".
                case identifier = "uid"
                case type
            }
        }
        
        /// Experiment identifier
        public let identifier: String

        /// Experiment name
        public let name: String

        /// Experiment group info
        public let group: Group

        init(identifier: String, name: String, group: Group) {
            self.identifier = identifier
            self.name = name
            self.group = group
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // None of the known keys means a schema break, not an incomplete
            // experiment.
            guard !container.allKeys.isEmpty else {
                let context = DecodingError.Context(codingPath: container.codingPath, debugDescription: "Experiment carries none of the expected keys")
                throw DecodingError.dataCorrupted(context)
            }

            // Same tolerance as Group: incomplete experiment metadata must not
            // cost the host the remote config that carries it.
            identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            let decodedGroup: Group? = try? container.decodeIfPresent(Group.self, forKey: .group)
            group = decodedGroup ?? Group()
        }

        private enum CodingKeys: String, CodingKey {
            // The backend names every entity identifier "uid".
            case identifier = "uid"
            case name
            case group
        }
    }
}
