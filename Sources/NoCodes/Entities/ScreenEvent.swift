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
  let pageIndex: Int?
  let happenedAt: Int

  init(type: ScreenEventType, screenUid: String, pageIndex: Int? = nil) {
    self.type = type
    self.screenUid = screenUid
    self.pageIndex = pageIndex
    self.happenedAt = Int(Date().timeIntervalSince1970)
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case screenUid = "screen_uid"
    case pageIndex = "page_index"
    case happenedAt = "happened_at"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(screenUid, forKey: .screenUid)
    if let pageIndex {
      try container.encode(pageIndex, forKey: .pageIndex)
    }
    try container.encode(happenedAt, forKey: .happenedAt)
  }
}
