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
    let event: ScreenEvent = Self.timestamped(event)
    guard Self.satisfiesBackendLimits(event) else {
      logger.warning(LoggerInfoMessages.screenEventRejected.rawValue)
      return
    }

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
        // The backend validates a batch all-or-nothing, so a rejected one
        // stays rejected: re-buffering it would retry it forever and the
        // buffer would never drain again.
        let isRejected: Bool = Self.isRejectedBatch(error)
        if isRejected {
          logger.error(LoggerInfoMessages.screenEventBatchRejected.rawValue)
        }
        queue.sync(flags: .barrier) {
          // Re-buffer events on failure so they can be retried on next flush
          if !isRejected {
            buffer.insert(contentsOf: eventsToSend, at: 0)
            // Drop oldest events if buffer exceeds max size
            if buffer.count > Self.maxBufferSize {
              buffer = Array(buffer.suffix(Self.maxBufferSize))
            }
          }
          isFlushing = false
          // Deliberately not re-armed: an immediate retry would spin against a
          // transport that is already failing.
          isFlushPending = false
        }
      }
    }
  }

  /// Whether the batch was refused by the backend rather than lost on the way
  /// to it: any 4xx but 429, which is throttling and clears on its own.
  private static func isRejectedBatch(_ error: Error) -> Bool {
    guard let noCodesError = error as? NoCodesError,
          let statusCode = noCodesError.additionalInfo?[ErrorConstants.statusCodeKey.rawValue] as? Int else { return false }

    return (ResponseCode.clientErrorMin.rawValue...ResponseCode.clientErrorMax.rawValue).contains(statusCode)
      && statusCode != ResponseCode.tooManyRequests.rawValue
  }

  // MARK: - Backend limits

  private static let happenedAtKey: String = "happened_at"
  private static let screenUidKey: String = "screen_uid"
  private static let pageIndexKey: String = "page_index"
  private static let typeKey: String = "type"
  private static let pageViewType: String = "screen_page_view"

  /// The oldest `happened_at` the backend accepts: 2020-01-01 UTC.
  private static let earliestHappenedAt: Int = 1_577_836_800

  /// How far into the future a `happened_at` may point: 24 hours.
  private static let happenedAtLookahead: Int = 86_400

  /// Above this a timestamp cannot be seconds (that would be the year 5138), so
  /// it is milliseconds — what a screen's JS produces by default.
  private static let millisecondThreshold: Int = 100_000_000_000

  private static let maxScreenUidLength: Int = 255
  private static let maxPageIndex: Int = 10_000

  /// Events from the screen runtime carry no timestamp of their own, and the
  /// backend requires one on every record of the batch. A timestamp the screen
  /// did author reaches here in whatever unit its JS used, and milliseconds are
  /// the JS default — left alone they read as a date far in the future and cost
  /// the event its place in the batch.
  private static func timestamped(_ event: ScreenEvent) -> ScreenEvent {
    var data: [String: AnyHashable] = event.data

    if let happenedAt = Self.intValue(data[Self.happenedAtKey]) {
      guard happenedAt >= Self.millisecondThreshold else { return event }

      data[Self.happenedAtKey] = happenedAt / 1000
    } else {
      data[Self.happenedAtKey] = Int(Date().timeIntervalSince1970)
    }

    return ScreenEvent(data: data)
  }

  /// Whether the backend would accept this record. One that it would not takes
  /// the whole batch down with it (validation is all-or-nothing), so it is
  /// dropped here instead of being buffered.
  private static func satisfiesBackendLimits(_ event: ScreenEvent) -> Bool {
    guard let screenUid = event.data[Self.screenUidKey] as? String,
          !screenUid.isEmpty,
          screenUid.count <= Self.maxScreenUidLength else { return false }

    guard let happenedAt = Self.intValue(event.data[Self.happenedAtKey]),
          happenedAt >= Self.earliestHappenedAt,
          happenedAt <= Int(Date().timeIntervalSince1970) + Self.happenedAtLookahead else { return false }

    guard event.data[Self.typeKey] as? String == Self.pageViewType else { return true }

    guard let pageIndex = Self.intValue(event.data[Self.pageIndexKey]),
          (0...Self.maxPageIndex).contains(pageIndex) else { return false }

    return true
  }

  /// The screen runtime hands its numbers over as `NSNumber`, and a payload
  /// that travelled through JSON may spell them as strings.
  private static func intValue(_ value: AnyHashable?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let stringValue = value as? String {
      return Int(stringValue)
    }

    return nil
  }
}
