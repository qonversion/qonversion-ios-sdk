//
//  UserServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 10.03.2024.
//

import Foundation

protocol UserServiceInterface {

    func user() async throws -> Qonversion.User

    func createUser() async throws -> Qonversion.User

    func generateUserId() -> String

    /// Returns the Qonversion user id linked to the given external identity,
    /// or nil when the identity is not linked yet (backend 404).
    func identity(for externalId: String) async throws -> String?

    /// Links the given external identity to the given Qonversion user id.
    /// Returns the resulting Qonversion user id the SDK must use onward.
    func createIdentity(externalId: String, userId: String) async throws -> String
}
