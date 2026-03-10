//
//  ScreenEventsServiceInterface.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

protocol ScreenEventsServiceInterface {

  /// Record a screen event. The event is buffered locally and sent in a batch later.
  func track(event: ScreenEvent)

  /// Flush all buffered events to the backend immediately.
  func flush()
}

#endif
