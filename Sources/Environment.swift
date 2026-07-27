//
//  Environment.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// The store environment the app runs against. It is sent with the user
    /// creation request, so the backend can keep sandbox data apart from
    /// production data.
    public enum Environment: String, Sendable {

        /// The App Store. The default.
        case production = "prod"

        /// The sandbox: TestFlight builds, Xcode runs and StoreKit testing.
        case sandbox
    }
}
