//
//  ScreenEventType.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

enum ScreenEventType: String, Encodable {
  case screenShown = "screen_shown"
  case screenClosed = "screen_closed"
  case ctaTap = "screen_cta_tap"
  case pageView = "screen_page_view"
}

#endif
