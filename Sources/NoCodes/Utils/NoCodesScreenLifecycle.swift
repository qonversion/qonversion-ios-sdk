//
//  NoCodesScreenLifecycle.swift
//  NoCodes
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

/// Why a screen stopped being visible.
enum NoCodesScreenLeave: Equatable {

  /// The screen is gone for good: its flow is over.
  case permanent

  /// The screen is only covered, usually by another screen pushed on top of it.
  case temporary
}

/// Presentation-layer decisions kept as pure functions: the presentation layer
/// itself is iOS only and needs a live UIKit hierarchy.
enum NoCodesScreenLifecycle {

  static func leave(isBeingDismissed: Bool, isMovingFromParent: Bool) -> NoCodesScreenLeave {
    return isBeingDismissed || isMovingFromParent ? .permanent : .temporary
  }

  /// A cancelled load belongs to a screen the user already left; applying it
  /// would announce a screen after the flow reported itself finished.
  static func shouldApplyLoadedScreen(isCancelled: Bool) -> Bool {
    return !isCancelled
  }

  /// Whether a screen that is going away ends the whole flow. A host-driven
  /// pop or dismiss has to end it just like the SDK-driven close, but popping
  /// the top of a multi-screen flow leaves the one below it on screen.
  static func reportsFinished(leave: NoCodesScreenLeave, hasRemainingFlowScreen: Bool) -> Bool {
    return leave == .permanent && !hasRemainingFlowScreen
  }

  /// `nil` for every route UIKit would silently drop, leaving the screen off
  /// screen while the call still looks like it worked.
  static func presentationTarget(style: NoCodesPresentationStyle, hasHost: Bool, hostHasNavigationController: Bool, hostIsAlreadyPresenting: Bool) -> NoCodesPresentationTarget? {
    guard hasHost else { return nil }

    switch style {
    case .push:
      // A push goes into the navigation stack, so a modal already up is no obstacle.
      return hostHasNavigationController ? .push : nil
    case .popover:
      return hostIsAlreadyPresenting ? nil : .popover
    case .fullScreen:
      return hostIsAlreadyPresenting ? nil : .modal
    }
  }
}

/// Where the coordinator puts a screen it is about to show.
enum NoCodesPresentationTarget: Equatable {

  /// Pushed onto the host's navigation stack.
  case push

  /// Presented as a popover anchored to the host.
  case popover

  /// Presented modally, wrapped into the No-Codes navigation controller.
  case modal
}

/// What the flow coordinator has to do after a flow event. Every host callback
/// the flow can send is one of these — exactly one finish per flow.
enum NoCodesFlowEffect: Equatable {

  /// Dismiss the visible screen; its dismissal comes back as `screenFinished()`.
  case dismissVisibleScreen

  /// Tell the host the flow is over.
  case reportFinished

  /// Tell the host the screen it asked for could not be put on screen.
  case reportFailedToPresent
}

/// What a presentation that reached its presentation point may do.
enum NoCodesPresentationOutcome: Equatable {

  case present

  /// The host closed the flow first; the effects carry what is left to report.
  case cancelled(effects: [NoCodesFlowEffect])
}

/// Remembers a `close` that lands while a screen is still being presented —
/// that window has no view controller to act on — and cancels the presentations
/// it raced instead of dropping the close.
struct NoCodesPresentationGate {

  /// Identifies one presentation from its start to its presentation point.
  /// Two `showScreen` calls can be in flight at once, and a close has to reach
  /// both of them, not whichever one comes back first.
  struct Token: Equatable {

    fileprivate let generation: UInt64
  }

  private var nextGeneration: UInt64 = 0
  private var inFlightCount: Int = 0
  /// Every token up to and including this generation was cancelled by a close.
  private var cancelledThroughGeneration: UInt64?
  /// The close found nothing on screen to dismiss, so the first cancelled
  /// presentation is what reports the flow over.
  private var cancellationOwesFinish = false
  private var hasVisibleScreen = false

  mutating func presentationStarted() -> Token {
    let generation: UInt64 = nextGeneration
    nextGeneration += 1
    inFlightCount += 1

    return Token(generation: generation)
  }

  /// Call once the screen is about to be put on screen. Deliberately does not
  /// mark it visible yet — the coordinator still has to find a host.
  mutating func presentationReady(_ token: Token) -> NoCodesPresentationOutcome {
    inFlightCount = max(0, inFlightCount - 1)

    guard let cancelledThroughGeneration, token.generation <= cancelledThroughGeneration else { return .present }

    let reportsFinished: Bool = cancellationOwesFinish
    cancellationOwesFinish = false

    return .cancelled(effects: reportsFinished ? [.reportFinished] : [])
  }

  /// Call only once the push or the present actually ran: arming earlier leaves
  /// a close dismissing a controller whose dismissal completion never fires.
  mutating func screenPresented() {
    hasVisibleScreen = true
  }

  /// Call when the allowed presentation could not happen at all. A screen
  /// already up survives it, so the flow is only finished when there is none.
  func presentationUnavailable() -> [NoCodesFlowEffect] {
    return hasVisibleScreen ? [.reportFailedToPresent] : [.reportFailedToPresent, .reportFinished]
  }

  /// A close has to reach the visible screen and every presentation in flight.
  /// Presentations started after it are new requests and go ahead.
  mutating func closeRequested() -> [NoCodesFlowEffect] {
    let closesVisibleScreen: Bool = hasVisibleScreen
    hasVisibleScreen = false

    if nextGeneration > 0 {
      cancelledThroughGeneration = nextGeneration - 1
    }
    cancellationOwesFinish = !closesVisibleScreen && inFlightCount > 0

    return closesVisibleScreen ? [.dismissVisibleScreen] : []
  }

  /// Call when the screen went away, on request or on its own.
  mutating func screenFinished() -> [NoCodesFlowEffect] {
    hasVisibleScreen = false

    return [.reportFinished]
  }
}
