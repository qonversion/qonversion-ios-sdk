//
//  UserManagerInterface.swift
//  Qonversion
//

import Foundation

/// Owns the user lifecycle: single-flight creation, identity linking, logout.
///
/// `obtainUser()` is the gate every data-sending flow (properties, purchases,
/// device, attribution) must pass before firing its request: it guarantees the
/// backend user exists, creating it at most once no matter how many callers
/// arrive concurrently, and — when an identify is pending — releases waiters
/// only after the identity has been sent.
protocol UserManagerInterface {

    /// Ensures the backend user exists and any pending identity is sent, then
    /// returns the current user. Concurrent callers share one in-flight
    /// creation request and all receive the same user. On creation failure the
    /// gate resets so the next caller retries.
    @discardableResult
    func obtainUser() async throws -> Qonversion.User

    /// Links the current user to the integrator's external user id.
    /// If the external id is already linked to another Qonversion user,
    /// the SDK switches to that user.
    @discardableResult
    func identify(_ externalId: String) async throws -> Qonversion.User

    /// Unlinks the current identity and resets to a fresh anonymous user.
    func logout() async

    /// Returns up-to-date info about the current user from the backend.
    func userInfo() async throws -> Qonversion.User
}
