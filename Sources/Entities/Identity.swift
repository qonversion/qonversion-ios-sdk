//
//  Identity.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// Link between an integrator's external user id and a Qonversion user.
    struct Identity: Decodable {

        /// The integrator's external user id.
        let id: String

        /// The Qonversion user id the external id is linked to.
        let userId: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
        }
    }
}
