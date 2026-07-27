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
struct NoCodesPresentationGate {

  private var isPresenting = false
  private var closeRequestedWhilePresenting = false

  mutating func presentationStarted() {
    isPresenting = true
    // A close left over from an abandoned presentation must not take this one
    // down with it.
    closeRequestedWhilePresenting = false
  }

  /// Call once the screen is about to be put on screen.
  ///
  /// - Returns: whether the presentation should still happen.
  mutating func presentationReady() -> Bool {
    isPresenting = false
    let shouldPresent: Bool = !closeRequestedWhilePresenting
    closeRequestedWhilePresenting = false

    return shouldPresent
  }

  /// - Returns: whether the close can be applied to a presented screen now.
  ///   When it cannot, the gate has recorded it and the presentation in flight
  ///   will be cancelled instead.
  mutating func closeRequested() -> Bool {
    guard isPresenting else { return true }

    closeRequestedWhilePresenting = true

    return false
  }
}
