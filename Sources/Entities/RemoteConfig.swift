//
//  RemoteConfig.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    /// Remote configuration, created via Qonversion Dashboard
    // @unchecked: the payload dictionary carries JSON plist values only.
    public struct RemoteConfig: Decodable, @unchecked Sendable {
        
        /// Source of the remote configuration
        public struct Source: Decodable, Sendable {

            /// Possible assignment types of the remote configuration
            public enum AssignmentType: String, Decodable, Sendable {
                
                /// Unknown assignment type
                case unknown // todo use as default
                
                /// Automatically assignment type
                case auto
                
                /// Manual assignment type
                case manual
            }

            /// Possible source types of the remote configuration
            public enum SourceType: String, Decodable, Sendable {
                
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

            /// Remote configuration context key, or `nil` when the
            /// configuration is not bound to one. A context key the backend
            /// sends as an empty string means the same thing and is normalized
            /// to `nil`, so a check for `""` never matches — compare against
            /// `nil`, or use ``Qonversion/RemoteConfigList/remoteConfigForEmptyContextKey()``.
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
                // An object carrying none of the known keys is a schema break,
                // not an incomplete source. Failing here is what still lets the
                // lossy list drop the row instead of surfacing an empty source.
                guard !container.allKeys.isEmpty else {
                    let context = DecodingError.Context(codingPath: container.codingPath, debugDescription: "Remote config source carries none of the expected keys")
                    throw DecodingError.dataCorrupted(context)
                }

                // Metadata keys decode leniently: a source missing one of them
                // used to fail, and a failed source took the whole config —
                // payload included — with it. The context key still decides
                // where the config is served from, so the config stays usable.
                identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
                name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
                // Unknown backend values must not fail the whole config decode.
                let typeStr: String? = try container.decodeIfPresent(String.self, forKey: .type)
                type = typeStr.flatMap { SourceType(rawValue: $0) } ?? .unknown
                let assignmentTypeStr: String? = try container.decodeIfPresent(String.self, forKey: .assignmentType)
                assignmentType = assignmentTypeStr.flatMap { AssignmentType(rawValue: $0) } ?? .unknown
                let contextKeyStr: String? = try container.decodeIfPresent(String.self, forKey: .contextKey)
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

        /// Remote configuration source, or nil when the backend reports none.
        public let source: Source?

        init(payload: [String: String]?, experiment: Experiment?, source: Source?) {
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

            // Absent keys must decode like explicit nulls — a config without
            // an experiment is the normal shape, not a decode failure.
            experiment = try container.decodeIfPresent(Experiment.self, forKey: .experiment)
            // The backend serializes the source from a pointer without
            // omitempty, so an unassigned config arrives with an explicit
            // null — that is a config without a source, not a broken payload.
            source = try container.decodeIfPresent(Source.self, forKey: .source)
        }
        
        // MARK: - Private
        
        private enum CodingKeys: String, CodingKey {
            case payload
            case experiment
            case source
        }
    }
}
