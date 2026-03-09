//
//  ScreenEventType.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

/// SDK-originated screen lifecycle events only.
/// JS-originated events (e.g. screen_cta_tap, screen_page_view) are passed through
/// without validation against this enum — see `handle(screenAnalyticsAction:)`.
enum ScreenEventType: String, Encodable {
  case screenShown = "screen_shown"
  case screenClosed = "screen_closed"
}

#endif
