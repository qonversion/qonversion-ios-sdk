//
//  Experiment.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 11.04.2024.
//

import Foundation

extension Qonversion {

    public class Experiment: Decodable {
        // Experiment identifier
        public let identifier: String

        // Experiment name
        public let name: String

        // Experiment group info
        public let group: Group

        init(identifier: String, name: String, group: Group) {
            self.identifier = identifier
            self.name = name
            self.group = group
        }
    }
}
