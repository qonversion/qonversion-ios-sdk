//
//  ScreenEventsService.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation
import Qonversion

final class ScreenEventsService: ScreenEventsServiceInterface {

  private let requestProcessor: RequestProcessorInterface
  private let logger: LoggerWrapper

  /// Thread-safe buffer for accumulated events.
  private let queue = DispatchQueue(label: "io.qonversion.nocodes.screenevents", attributes: .concurrent)
  private var buffer: [ScreenEvent] = []

  /// Maximum number of events to accumulate before auto-flushing.
  private static let batchSize = 10

  /// Maximum number of events to keep in the retry buffer.
  /// Oldest events are dropped when this limit is exceeded.
  private static let maxBufferSize = 100

  init(requestProcessor: RequestProcessorInterface, logger: LoggerWrapper) {
    self.requestProcessor = requestProcessor
    self.logger = logger
  }

  func track(event: ScreenEvent) {
    var shouldFlush = false
    queue.sync(flags: .barrier) {
      buffer.append(event)
      shouldFlush = buffer.count >= Self.batchSize
    }
    logger.debug("Tracked screen event: \(event.type.rawValue) for screen \(event.screenUid)")
    if shouldFlush {
      flush()
    }
  }

  func flush() {
    let eventsToSend: [ScreenEvent] = queue.sync(flags: .barrier) {
      let copy = buffer
      buffer.removeAll()
      return copy
    }

    guard !eventsToSend.isEmpty else { return }

    logger.debug("Flushing \(eventsToSend.count) screen events")

    Task {
      do {
        let userInfo = try await Qonversion.shared().userInfo()
        let uid = userInfo.qonversionId

        let encoder = JSONEncoder()
        let eventsData = try encoder.encode(eventsToSend)
        guard let eventDicts = try JSONSerialization.jsonObject(with: eventsData) as? [[String: AnyHashable]] else {
          throw NSError(domain: "io.qonversion.nocodes", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize screen events"])
        }

        let request = Request.sendScreenEvents(uid: uid, body: eventDicts)
        try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        logger.debug(LoggerInfoMessages.screenEventFlushed.rawValue)
      } catch {
        logger.error(LoggerInfoMessages.screenEventTrackingFailed.rawValue)
        // Re-buffer events on failure so they can be retried on next flush
        queue.sync(flags: .barrier) {
          buffer.insert(contentsOf: eventsToSend, at: 0)
          // Drop oldest events if buffer exceeds max size
          if buffer.count > Self.maxBufferSize {
            buffer = Array(buffer.suffix(Self.maxBufferSize))
          }
        }
      }
    }
  }
}
