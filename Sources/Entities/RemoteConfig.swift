//
//  RemoteConfig.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    /// Remote configuration, created via Qonversion Dashboard
    public struct RemoteConfig: Decodable {
        
        /// Source of the remote configuration
        public struct Source: Decodable {

            /// Possible assignment types of the remote configuration
            public enum AssignmentType: String, Decodable {
                
                /// Unknown assignment type
                case unknown // todo use as default
                
                /// Automatically assignment type
                case auto
                
                /// Manual assignment type
                case manual
            }

            /// Possible source types of the remote configuration
            public enum SourceType: String, Decodable {
                
                /// Unknown source type
                case unknown // todo use as default
                
                /// Experiment control group source type
                case experimentControlGroup = "experiment_control_group"
                
                /// Experiment treatment group source type
                case experimentTreatmentGroup = "experiment_treatment_group"
                
                /// Remote configuration source type
                case remoteConfiguration = "remote_configuration"
            }

            /// Remote configuration source name. Can be the experiment identifier or default remote configuration identifier, depending on the payload's source.
            public let identifier: String

            /// Remote configuration source name. Can be the experiment name or default remote configuration name, depending on the payload's source.
            public let name: String

            /// Remote configuration source type
            public let type: SourceType

            /// Remote config assignment type that indicates how the current payload was assigned to the user.
            public let assignmentType: AssignmentType

            /// Remote configuration context key. Empty string if not specified.
            public let contextKey: String?

            init(identifier: String, name: String, type: SourceType, assignmentType: AssignmentType, contextKey: String?) {
                self.identifier = identifier
                self.name = name
                self.type = type
                self.assignmentType = assignmentType
                self.contextKey = contextKey
            }

            public init(from decoder: Decoder) throws {
                let container: KeyedDecodingContainer = try decoder.container(keyedBy: CodingKeys.self)
                identifier = try container.decode(String.self, forKey: .identifier)
                name = try container.decode(String.self, forKey: .name)
                type = try container.decode(SourceType.self, forKey: .type)
                assignmentType = try container.decode(AssignmentType.self, forKey: .assignmentType)
                let contextKeyStr: String? = try container.decode(String?.self, forKey: .contextKey)
                contextKey = contextKeyStr?.isEmpty == false ? contextKeyStr : nil
            }
            
            // MARK: - Private

            private enum CodingKeys: String, CodingKey {
                case identifier = "uid"
                case name
                case type
                case assignmentType = "assignment_type"
                case contextKey = "context_key"
            }
        }

        /// Remote config payload
        public let payload: [String: Any]?

        /// Experiment info
        public let experiment: Experiment?

        /// Remote configuration source
        public let source: Source

        init(payload: [String: String]?, experiment: Experiment?, source: Source) {
            self.payload = payload
            self.experiment = experiment
            self.source = source
        }

        public init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer = try decoder.container(keyedBy: CodingKeys.self)
            if let payloadContainer: KeyedDecodingContainer = try? container.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: .payload) {
                payload = decode(fromObject: payloadContainer)
            } else {
                payload = nil
            }

            experiment = try container.decode(Experiment?.self, forKey: .experiment)
            source = try container.decode(Source.self, forKey: .source)
        }
        
        // MARK: - Private
        
        private enum CodingKeys: String, CodingKey {
            case payload
            case experiment
            case source
        }
    }
}
