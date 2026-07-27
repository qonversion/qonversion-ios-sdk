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

  /// Cached user ID to avoid resolving on every flush.
  private var cachedUserId: String?

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
    logger.debug("Tracked screen event: \(event.data["type"] ?? "unknown")")
    if shouldFlush {
      flush()
    }
  }

  func flush() {
    let eventsToSend: [ScreenEvent] = queue.sync(flags: .barrier) {
      guard !isFlushing else { return [] }
      isFlushing = true
      let copy = buffer
      buffer.removeAll()
      return copy
    }

    guard !eventsToSend.isEmpty else { return }

    logger.debug("Flushing \(eventsToSend.count) screen events")

    Task {
      do {
        let uid: String
        if let cached = queue.sync(execute: { cachedUserId }) {
          uid = cached
        } else {
          let resolvedUid: String = try await userIdProvider()
          uid = resolvedUid
          queue.sync(flags: .barrier) { cachedUserId = resolvedUid }
        }

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
