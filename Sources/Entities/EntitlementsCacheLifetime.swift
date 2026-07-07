//
//  EntitlementsCacheLifetime.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// How long cached entitlements stay eligible for the local fallback when
    /// the backend is unreachable.
    public enum EntitlementsCacheLifetime {
        case week
        case twoWeeks
        case month
        case twoMonths
        case threeMonths
        case sixMonths
        case year
        case unlimited

        var seconds: TimeInterval {
            let day: TimeInterval = 24 * 60 * 60
            switch self {
            case .week: return 7 * day
            case .twoWeeks: return 14 * day
            case .month: return 30 * day
            case .twoMonths: return 60 * day
            case .threeMonths: return 90 * day
            case .sixMonths: return 180 * day
            case .year: return 365 * day
            case .unlimited: return .greatestFiniteMagnitude
            }
        }
    }
}
