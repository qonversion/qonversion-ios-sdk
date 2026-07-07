//
//  EntitlementsUpdateListener.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// Receives entitlements updated by out-of-band transactions the SDK
    /// processed in subscription-management mode: Ask to Buy approvals,
    /// renewals, purchases on other devices.
    public protocol EntitlementsUpdateListener: AnyObject {
        func didReceiveUpdatedEntitlements(_ entitlements: [String: Qonversion.Entitlement])
    }
}
