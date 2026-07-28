//
//  ScreenEventsService.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation
import Qonversion

// @unchecked: `buffer` and `isFlushing` are only ever touched inside `queue`
// (barrier writes, sync reads).
final class ScreenEventsService: ScreenEventsServiceInterface, @unchecked Sendable {

  /// Resolves the Qonversion user id the events are reported for.
  typealias UserIdProvider = @Sendable () async throws -> String

  private let requestProcessor: RequestProcessorInterface
  private let logger: LoggerWrapper
  private let userIdProvider: UserIdProvider

  /// Thread-safe buffer for accumulated events.
  private let queue = DispatchQueue(label: "io.qonversion.nocodes.screenevents", attributes: .concurrent)
  private var buffer: [ScreenEvent] = []

  /// Guard against concurrent flush operations.
  private var isFlushing = false

  /// A flush that arrived while another one was in flight. It is honoured once
  /// that one returns — otherwise the events wait for the next `track` to cross
  /// the batch size, which for a closing screen never comes.
  private var isFlushPending = false

  /// Maximum number of events to accumulate before auto-flushing.
  private static let batchSize = 10

  /// Maximum number of events to keep buffered.
  /// Oldest events are dropped when this limit is exceeded.
  private static let maxBufferSize = 100

  init(requestProcessor: RequestProcessorInterface, logger: LoggerWrapper, userIdProvider: @escaping UserIdProvider = ScreenEventsService.currentUserId) {
    self.requestProcessor = requestProcessor
    self.logger = logger
    self.userIdProvider = userIdProvider
  }

  private static let currentUserId: UserIdProvider = {
    let userInfo: Qonversion.User = try await Qonversion.shared.userInfo()

    return userInfo.id
  }

  func track(event: ScreenEvent) {
    var shouldFlush = false
    queue.sync(flags: .barrier) {
      buffer.append(event)
      // A hung flush latches `isFlushing`, so the cap has to be applied here too.
      if buffer.count > Self.maxBufferSize {
        buffer = Array(buffer.suffix(Self.maxBufferSize))
      }
      shouldFlush = buffer.count >= Self.batchSize
    }
    let eventType: String = event.data["type"] as? String ?? "unknown"
    logger.debug("Tracked screen event: \(eventType)")
    if shouldFlush {
      flush()
    }
  }

  func flush() {
    let eventsToSend: [ScreenEvent] = queue.sync(flags: .barrier) {
      // The emptiness check must precede raising the flag: an empty flush never
      // reaches the code that lowers it again.
      guard !buffer.isEmpty else { return [] }
      guard !isFlushing else {
        isFlushPending = true
        return []
      }
      isFlushing = true
      let copy: [ScreenEvent] = buffer
      buffer.removeAll()
      return copy
    }

    guard !eventsToSend.isEmpty else { return }

    logger.debug("Flushing \(eventsToSend.count) screen events")

    Task {
      do {
        // Resolved per flush on purpose: identify() between batches would
        // otherwise post the events to the previous user.
        let uid: String = try await userIdProvider()

        let eventDicts: [[String: AnyHashable]] = eventsToSend.map { $0.toMap() }
        let request = Request.sendScreenEvents(uid: uid, body: eventDicts)
        try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        logger.debug(LoggerInfoMessages.screenEventFlushed.rawValue)
        let shouldFlushAgain: Bool = queue.sync(flags: .barrier) {
          isFlushing = false
          let isWarranted: Bool = isFlushPending || buffer.count >= Self.batchSize
          isFlushPending = false

          return isWarranted && !buffer.isEmpty
        }
        if shouldFlushAgain {
          flush()
        }
      } catch {
        logger.error(LoggerInfoMessages.screenEventTrackingFailed.rawValue)
        // Re-buffer events on failure so they can be retried on next flush
        queue.sync(flags: .barrier) {
          buffer.insert(contentsOf: eventsToSend, at: 0)
          // Drop oldest events if buffer exceeds max size
          if buffer.count > Self.maxBufferSize {
            buffer = Array(buffer.suffix(Self.maxBufferSize))
          }
          isFlushing = false
          // Deliberately not re-armed: an immediate retry would spin against a
          // transport that is already failing.
          isFlushPending = false
        }
      }
    }
  }
}
