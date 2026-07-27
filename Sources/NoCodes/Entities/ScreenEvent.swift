//
//  ScreenEvent.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

/// The payload is kept hashable rather than `Any` so an event can cross into
/// the flushing task.
// @unchecked: `data` is a `let` whose values are the JSON scalars the SDK and
// the screen runtime produce (strings, numbers, booleans) — AnyHashable itself
// carries no Sendable guarantee.
struct ScreenEvent: @unchecked Sendable {
  let data: [String: AnyHashable]

  init(data: [String: AnyHashable]) {
    self.data = data
  }

  /// Builds an event from a raw JS payload, dropping the values that cannot be
  /// serialized (the wire format carries no such value either).
  init(rawData: [String: Any]) {
    var hashableData: [String: AnyHashable] = [:]
    for (key, value) in rawData {
      guard let hashableValue = value as? AnyHashable else { continue }

      hashableData[key] = hashableValue
    }

    self.data = hashableData
  }

  func toMap() -> [String: AnyHashable] {
    return data
  }
}
