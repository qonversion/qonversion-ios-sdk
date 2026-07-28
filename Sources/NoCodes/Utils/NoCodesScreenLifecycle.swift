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
/// that window has no view controller to act on — and cancels the presentation
/// it raced instead of dropping the close.
struct NoCodesPresentationGate {

  private var isPresenting = false
  private var closeRequestedWhilePresenting = false
  private var pendingCloseDismissedAVisibleScreen = false
  private var hasVisibleScreen = false

  mutating func presentationStarted() {
    isPresenting = true
    // A close left over from an abandoned presentation must not take this one down.
    closeRequestedWhilePresenting = false
    pendingCloseDismissedAVisibleScreen = false
  }

  /// Call once the screen is about to be put on screen. Deliberately does not
  /// mark it visible yet — the coordinator still has to find a host.
  mutating func presentationReady() -> NoCodesPresentationOutcome {
    isPresenting = false

    guard closeRequestedWhilePresenting else { return .present }

    let reportsFinished: Bool = !pendingCloseDismissedAVisibleScreen
    closeRequestedWhilePresenting = false
    pendingCloseDismissedAVisibleScreen = false

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

  /// A close has to reach both the visible screen and any presentation in flight.
  mutating func closeRequested() -> [NoCodesFlowEffect] {
    let closesVisibleScreen: Bool = hasVisibleScreen
    hasVisibleScreen = false

    if isPresenting {
      closeRequestedWhilePresenting = true
      pendingCloseDismissedAVisibleScreen = closesVisibleScreen
    }

    return closesVisibleScreen ? [.dismissVisibleScreen] : []
  }

  /// Call when the screen went away, on request or on its own.
  mutating func screenFinished() -> [NoCodesFlowEffect] {
    hasVisibleScreen = false

    return [.reportFinished]
  }
}
