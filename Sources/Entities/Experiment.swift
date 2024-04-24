//
//  Experiment.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    /// Experiment, created via Qonversion Dashboard
    public struct Experiment: Decodable {
        
        /// Information about the experiment group
        public struct Group: Decodable {

            /// Possible types of the experiment group
            public enum GroupType: String, Decodable {
                
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
    }
}
