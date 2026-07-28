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

  /// The screen is only covered, usually by another screen pushed on top of it,
  /// and will come back.
  case temporary
}

/// The screen lifecycle decisions taken by the presentation layer.
///
/// The presentation layer itself is iOS only and needs a live UIKit hierarchy,
/// so the branches that are worth being sure about live here as plain functions
/// over the inputs instead.
enum NoCodesScreenLifecycle {

  static func leave(isBeingDismissed: Bool, isMovingFromParent: Bool) -> NoCodesScreenLeave {
    return isBeingDismissed || isMovingFromParent ? .permanent : .temporary
  }

  /// Whether a finished screen load may still notify the delegate, report the
  /// screen as shown and render into the web view.
  ///
  /// A cancelled load belongs to a screen the user has already left, and acting
  /// on it would announce a screen after the flow reported itself finished.
  static func shouldApplyLoadedScreen(isCancelled: Bool) -> Bool {
    return !isCancelled
  }
}

/// Reconciles a `close` that arrives while a screen is still being presented.
///
/// Presenting is asynchronous and there is no view controller to hold on to
/// until it is well under way, so a close landing in that window has nothing to
/// act on. Rather than dropping it, the gate remembers it and cancels the
/// presentation it raced.
/// What a `close` has to act on.
struct NoCodesCloseOutcome: Equatable {

  /// A screen is on screen and has to be dismissed.
  let closesVisibleScreen: Bool

  /// A presentation is in flight and will not reach the screen.
  let cancelsPendingPresentation: Bool
}

/// What a presentation that reached its presentation point may do.
enum NoCodesPresentationOutcome: Equatable {

  case present

  /// The host closed the flow first. `reportsFinished` is false when that same
  /// close dismissed a visible screen, which reports the flow finished itself.
  case cancelled(reportsFinished: Bool)
}

struct NoCodesPresentationGate {

  private var isPresenting = false
  private var closeRequestedWhilePresenting = false
  private var pendingCloseDismissedAVisibleScreen = false
  private var hasVisibleScreen = false

  mutating func presentationStarted() {
    isPresenting = true
    // A close left over from an abandoned presentation must not take this one
    // down with it.
    closeRequestedWhilePresenting = false
    pendingCloseDismissedAVisibleScreen = false
  }

  /// Call once the screen is about to be put on screen.
  mutating func presentationReady() -> NoCodesPresentationOutcome {
    isPresenting = false

    guard closeRequestedWhilePresenting else {
      hasVisibleScreen = true

      return .present
    }

    let reportsFinished: Bool = !pendingCloseDismissedAVisibleScreen
    closeRequestedWhilePresenting = false
    pendingCloseDismissedAVisibleScreen = false

    return .cancelled(reportsFinished: reportsFinished)
  }

  /// A show started while the previous screen is still up raises the very same
  /// in-flight state, so a close landing there has to reach both: the screen
  /// the user is looking at and the one on its way.
  mutating func closeRequested() -> NoCodesCloseOutcome {
    let closesVisibleScreen: Bool = hasVisibleScreen
    hasVisibleScreen = false

    if isPresenting {
      closeRequestedWhilePresenting = true
      pendingCloseDismissedAVisibleScreen = closesVisibleScreen
    }

    return NoCodesCloseOutcome(closesVisibleScreen: closesVisibleScreen, cancelsPendingPresentation: isPresenting)
  }

  /// Call when the screen ended on its own, so a later close does not try to
  /// dismiss a screen that is already gone.
  mutating func screenFinished() {
    hasVisibleScreen = false
  }
}
