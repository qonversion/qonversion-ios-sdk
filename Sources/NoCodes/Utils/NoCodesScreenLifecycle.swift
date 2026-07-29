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

  /// Whether a screen action can push a follow-up screen. A screen presented
  /// as a popover has no navigation controller of its own, and pushing onto
  /// `nil` is a silent no-op the host used to hear about as a success.
  static func canPushFollowUpScreen(hasNavigationController: Bool) -> Bool {
    return hasNavigationController
  }

  /// Whether the host is told this action started executing. The actions the
  /// screen runtime uses to talk to the SDK are not host-visible work; every
  /// other type is announced, and an announced action owes the host exactly one
  /// finished-executing or failed-to-execute callback afterwards.
  static func announcesExecution(actionType: NoCodesActionType) -> Bool {
    switch actionType {
    case .loadProducts, .screenAnalytics, .getContext, .purchaseLoaderPresent, .showScreen:
      return false
    default:
      return true
    }
  }

  /// Who has to hear that an action could not be carried out.
  static func failureReport(actionType: NoCodesActionType) -> NoCodesActionFailureReport {
    return actionType == .purchase ? .hostAndScreen : .host
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

/// Where the report for an action the SDK could not carry out has to go.
enum NoCodesActionFailureReport: Equatable {

  /// The host is told; the screen expects nothing back.
  case host

  /// The host is told and the screen is sent a failure event as well. A screen
  /// that renders its own purchase loader only takes it down when one arrives.
  case hostAndScreen
}

/// The `screen_shown` / `screen_closed` pair one screen owes the analytics
/// backend, kept as a value so a whole screen lifetime can be traced without a
/// view hierarchy.
///
/// A screen opens a session whenever it becomes visible and closes it whenever
/// it stops being visible — including when it is merely covered by another
/// screen of the same flow. UIKit sends that `viewDidDisappear` once and never
/// sends another once the flow is torn down, so a session left open there was
/// only ever closed in `deinit`, long after the flow flushed its events.
struct NoCodesScreenSession {

  private var isOpen = false

  /// Marks a `screen_shown`. Returns whether the event has to be sent: a screen
  /// already counted as shown must not be counted again.
  mutating func trackShown() -> Bool {
    guard !isOpen else { return false }

    isOpen = true

    return true
  }

  /// Marks a `screen_closed`. Returns whether the event has to be sent: only an
  /// open session owes one, so the several routes out of a screen — the
  /// deliberate close, `viewDidDisappear`, `deinit` — produce a single event.
  mutating func trackClosed() -> Bool {
    guard isOpen else { return false }

    isOpen = false

    return true
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
  /// Screens that were put on screen and have not reported back yet. A flow can
  /// hold several at once — a second `showScreen` stacks on the first, and a
  /// screen can push further screens of its own — and it is over only once the
  /// last of them is gone.
  private var liveScreenCount: Int = 0
  /// A close already asked for every live screen, so a second one has nothing
  /// left to ask for until the flow ends.
  private var isClosing = false

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
    liveScreenCount += 1
    // A screen no earlier close could have reached, so closing again has
    // something to act on even while the previous dismissal is still settling.
    isClosing = false
  }

  /// Call when the allowed presentation could not happen at all. A screen
  /// already up survives it, so the flow is only finished when there is none.
  func presentationUnavailable() -> [NoCodesFlowEffect] {
    return liveScreenCount > 0 ? [.reportFailedToPresent] : [.reportFailedToPresent, .reportFinished]
  }

  /// A close has to reach every live screen and every presentation in flight.
  /// Presentations started after it are new requests and go ahead.
  mutating func closeRequested() -> [NoCodesFlowEffect] {
    let closesLiveScreens: Bool = liveScreenCount > 0 && !isClosing
    if closesLiveScreens {
      isClosing = true
    }

    if nextGeneration > 0 {
      cancelledThroughGeneration = nextGeneration - 1
    }
    // Only when nothing is on screen: a live screen reports the flow over on
    // its own once its dismissal comes back.
    cancellationOwesFinish = liveScreenCount == 0 && inFlightCount > 0

    return closesLiveScreens ? [.dismissVisibleScreen] : []
  }

  /// Call when a screen went away, on request or on its own.
  ///
  /// Only the last one ends the flow. A multi-screen flow has every one of its
  /// screens report — the dismissal takes them all — and a screen the
  /// coordinator never presented itself reports just the same, so anything past
  /// the last live one is an echo the host must not hear.
  mutating func screenFinished() -> [NoCodesFlowEffect] {
    guard liveScreenCount > 0 else { return [] }

    liveScreenCount -= 1

    guard liveScreenCount == 0 else { return [] }

    isClosing = false

    return [.reportFinished]
  }

  /// Call when the close found no screen left to dismiss after all. Nothing
  /// will report the flow over on its own then, so the report comes from here.
  mutating func nothingToDismiss() -> [NoCodesFlowEffect] {
    guard liveScreenCount > 0 else { return [] }

    liveScreenCount = 0
    isClosing = false

    return [.reportFinished]
  }
}
