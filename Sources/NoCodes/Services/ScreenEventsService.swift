//
//  ScreenEventsService.swift
//  NoCodes
//
//  Created by Claude on 10.02.2026.
//  Copyright (c) 2026 Qonversion Inc. All rights reserved.
//

import Foundation
import Qonversion

// @unchecked: `buffer`, `isFlushing` and `cachedUserId` are only ever touched
// inside `queue` (barrier writes, sync reads).
final class ScreenEventsService: ScreenEventsServiceInterface, @unchecked Sendable {

  /// Resolves the Qonversion user id the events are reported for. Injected so
  /// the batching logic can be exercised without a live SDK instance.
  typealias UserIdProvider = @Sendable () async throws -> String

  private let requestProcessor: RequestProcessorInterface
  private let logger: LoggerWrapper
  private let userIdProvider: UserIdProvider

  /// Thread-safe buffer for accumulated events.
  private let queue = DispatchQueue(label: "io.qonversion.nocodes.screenevents", attributes: .concurrent)
  private var buffer: [ScreenEvent] = []

  /// Guard against concurrent flush operations.
  private var isFlushing = false

  /// Maximum number of events to accumulate before auto-flushing.
  private static let batchSize = 10

  /// Maximum number of events to keep in the retry buffer.
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
      // The emptiness check belongs inside the barrier and before the flag is
      // raised: a flush that finds nothing to send never reaches the code that
      // lowers it again, so raising it first would latch the service off for
      // the rest of the process. Screen closes flush unconditionally, so an
      // empty flush is the common case, not the edge one.
      guard !isFlushing, !buffer.isEmpty else { return [] }
      isFlushing = true
      let copy: [ScreenEvent] = buffer
      buffer.removeAll()
      return copy
    }

    guard !eventsToSend.isEmpty else { return }

    logger.debug("Flushing \(eventsToSend.count) screen events")

    Task {
      do {
        // Resolved per flush on purpose: the host app can identify a different
        // user between batches, and a cached id would keep posting the events
        // to the previous user. The main SDK answers from its own cache, so
        // this costs nothing.
        let uid: String = try await userIdProvider()

        let eventDicts: [[String: AnyHashable]] = eventsToSend.map { $0.toMap() }
        let request = Request.sendScreenEvents(uid: uid, body: eventDicts)
        try await requestProcessor.process(request: request, responseType: EmptyApiResponse.self)
        logger.debug(LoggerInfoMessages.screenEventFlushed.rawValue)
        queue.sync(flags: .barrier) { isFlushing = false }
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
        }
      }
    }
  }
}
