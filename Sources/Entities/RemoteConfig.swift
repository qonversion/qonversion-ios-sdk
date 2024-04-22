//
//  RemoteConfig.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    public class RemoteConfig: Decodable {
        // Remote config payload
        public let payload: [String: Any]?

        // Experiment info
        public let experiment: Experiment?

        // Remote configuration source
        public let source: Source

        init(payload: [String: String]?, experiment: Experiment?, source: Source) {
            self.payload = payload
            self.experiment = experiment
            self.source = source
        }

        private enum CodingKeys: String, CodingKey {
            case payload
            case experiment
            case source
        }

        required public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let payloadContainer = try? container.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: .payload) {
                payload = decode(fromObject: payloadContainer)
            } else {
                payload = nil
            }

            experiment = try container.decode(Experiment?.self, forKey: .experiment)
            source = try container.decode(Source.self, forKey: .source)
        }
    }
}
