
//
//  ExperimentGroup.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion.Experiment {

    public class Group: Decodable {

        public enum GroupType: String, Decodable {
            case unknown
            case control
            case treatment
        }

        // Experiment group name
        public let name: String

        // Experiment group identifier
        public let identifier: String

        // Experiment group type
        public let type: GroupType

        init(name: String, identifier: String, type: GroupType) {
            self.name = name
            self.identifier = identifier
            self.type = type
        }
    }
}
