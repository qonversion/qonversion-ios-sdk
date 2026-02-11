//
//  ScreenEventType.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

enum ScreenEventType: String, Encodable {
  case screenShown = "screen_shown"
  case screenClosed = "screen_closed"
}
