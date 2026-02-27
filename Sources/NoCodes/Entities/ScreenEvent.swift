//
//  ScreenEvent.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

struct ScreenEvent {
  let data: [String: Any]

  func toMap() -> [String: AnyHashable] {
    var result: [String: AnyHashable] = [:]
    for (key, value) in data {
      if let hashable = value as? AnyHashable {
        result[key] = hashable
      }
    }
    return result
  }
}

#endif
