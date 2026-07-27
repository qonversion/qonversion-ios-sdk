//
//  RateLimiterInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

protocol RateLimiterInterface: Sendable {
    
    func validateRateLimit(for request: Request) -> NoCodesError?
}
