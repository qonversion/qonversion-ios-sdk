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
