//
//  RateLimiterInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 13.03.2024.
//

import Foundation

#if os(iOS)

protocol RateLimiterInterface {
    
    func validateRateLimit(for request: Request) -> NoCodesError?
}

#endif
