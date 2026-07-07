//
//  LaunchMode.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 28.03.2024.
//

import Foundation

extension Qonversion {
    
    /// Enum that describes the SDK launch mode.
    public enum LaunchMode {

        /// Analytics (observer) mode: the host app owns the purchase flow and
        /// the transaction lifecycle; the SDK only observes and reports.
        case analytics

        /// Subscription management mode: the SDK processes purchases and
        /// manages access to premium features (includes analytics).
        case subscriptionManagement
    }
}
