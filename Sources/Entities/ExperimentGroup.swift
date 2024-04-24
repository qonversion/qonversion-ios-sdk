
//
//  ExperimentGroup.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion.Experiment {

    /// Information about the experiment group
    public struct Group: Decodable {

        /// Possible types of the experiment group
        public enum GroupType: String, Decodable {
            case unknown
            case control
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
    }
}
