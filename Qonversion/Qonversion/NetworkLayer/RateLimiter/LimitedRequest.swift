//
//  LimitedRequest.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

struct LimitedRequest {
    
    public let timestamp: TimeInterval;
    public let hash: Int;
    
    init(timestamp: TimeInterval, hash: Int) {
        self.timestamp = timestamp
        self.hash = hash
    }
}
