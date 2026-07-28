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

  /// How the screen can reach the screen, given the host the coordinator
  /// resolved for it, or `nil` when nothing can put it there.
  ///
  /// Every route UIKit can silently drop counts as nothing: a push without a
  /// navigation controller and a presentation on a controller that is already
  /// presenting both leave the screen off screen while the call itself looks
  /// like it worked. The coordinator has to hear about that, or it arms itself
  /// for a screen the user will never see.
  static func presentationTarget(style: NoCodesPresentationStyle, hasHost: Bool, hostHasNavigationController: Bool, hostIsAlreadyPresenting: Bool) -> NoCodesPresentationTarget? {
    guard hasHost else { return nil }

    switch style {
    case .push:
      // A push goes into the navigation stack rather than on top of whatever
      // the host presents, so a modal already up does not stand in its way.
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

/// What the flow coordinator has to do after a flow event.
///
/// The coordinator is iOS only and needs a live UIKit hierarchy, so its
/// decisions are taken here and handed back as effects. Every callback the flow
/// can send the host is one of these, which is what makes the accounting — one
/// finish per flow, never none, never two — traceable without a view hierarchy.
enum NoCodesFlowEffect: Equatable {

  /// Dismiss the screen the user is looking at. Its dismissal comes back as
  /// ``NoCodesPresentationGate/screenFinished()``.
  case dismissVisibleScreen

  /// Tell the host the flow is over.
  case reportFinished

  /// Tell the host the screen it asked for could not be put on screen.
  case reportFailedToPresent
}

/// What a presentation that reached its presentation point may do.
enum NoCodesPresentationOutcome: Equatable {

  case present

  /// The host closed the flow first. The effects carry what is left to report:
  /// nothing when that same close dismissed a visible screen, since the
  /// dismissal reports the flow finished itself.
  case cancelled(effects: [NoCodesFlowEffect])
}

/// Reconciles a `close` that arrives while a screen is still being presented,
/// and keeps track of whether there is a screen on screen at all.
///
/// Presenting is asynchronous and there is no view controller to hold on to
/// until it is well under way, so a close landing in that window has nothing to
/// act on. Rather than dropping it, the gate remembers it and cancels the
/// presentation it raced.
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
  ///
  /// Deliberately does not treat the screen as visible yet: the coordinator
  /// still has to find something to present on, and until it has actually
  /// presented, a close has nothing to dismiss.
  mutating func presentationReady() -> NoCodesPresentationOutcome {
    isPresenting = false

    guard closeRequestedWhilePresenting else { return .present }

    let reportsFinished: Bool = !pendingCloseDismissedAVisibleScreen
    closeRequestedWhilePresenting = false
    pendingCloseDismissedAVisibleScreen = false

    return .cancelled(effects: reportsFinished ? [.reportFinished] : [])
  }

  /// Call once the screen really is on screen — the push or the present ran.
  ///
  /// Arming any earlier leaves a close dismissing a view controller that was
  /// never presented, and the dismissal completion that reports the flow
  /// finished never fires for one of those.
  mutating func screenPresented() {
    hasVisibleScreen = true
  }

  /// Call when the presentation ``presentationReady()`` allowed could not
  /// happen at all, so the host is not left waiting for a screen that will
  /// never appear.
  ///
  /// A screen already up is untouched by a presentation that never ran, so the
  /// flow is not over in that case and only the failure is reported.
  func presentationUnavailable() -> [NoCodesFlowEffect] {
    return hasVisibleScreen ? [.reportFailedToPresent] : [.reportFailedToPresent, .reportFinished]
  }

  /// A show started while the previous screen is still up raises the very same
  /// in-flight state, so a close landing there has to reach both: the screen
  /// the user is looking at and the one on its way.
  mutating func closeRequested() -> [NoCodesFlowEffect] {
    let closesVisibleScreen: Bool = hasVisibleScreen
    hasVisibleScreen = false

    if isPresenting {
      closeRequestedWhilePresenting = true
      pendingCloseDismissedAVisibleScreen = closesVisibleScreen
    }

    return closesVisibleScreen ? [.dismissVisibleScreen] : []
  }

  /// Call when the screen went away — dismissed on request, or ended on its own
  /// because the user tapped its close button — so a later close does not try
  /// to dismiss a screen that is already gone.
  mutating func screenFinished() -> [NoCodesFlowEffect] {
    hasVisibleScreen = false

    return [.reportFinished]
  }
}
