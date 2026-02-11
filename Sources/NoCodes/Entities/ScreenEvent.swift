//
//  ScreenEvent.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

struct ScreenEvent: Encodable {
  let type: ScreenEventType
  let screenUid: String
  let happenedAt: Int

  init(type: ScreenEventType, screenUid: String) {
    self.type = type
    self.screenUid = screenUid
    self.happenedAt = Int(Date().timeIntervalSince1970)
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case screenUid = "screen_uid"
    case happenedAt = "happened_at"
  }
}
