//
//  IntroEligibility.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// The user's eligibility for an introductory or trial offer of a product.
    public enum IntroEligibilityStatus: Sendable {

        /// The eligibility could not be determined (e.g. the store product is
        /// not loaded or the system is too old to answer).
        case unknown

        /// The product has no introductory or trial offer configured.
        case nonIntroOrTrialProduct

        /// The user is eligible for the introductory offer.
        case eligible

        /// The user has already consumed the introductory offer.
        case ineligible
    }
}
