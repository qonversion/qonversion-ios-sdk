//
//  NoCodesScreenLifecycleTests.swift
//  NoCodesTests
//
//  The screen lifecycle decisions the iOS-only presentation code delegates here.
//

import XCTest
@testable import NoCodes

final class NoCodesScreenLeaveTests: XCTestCase {

    func testBeingDismissedIsAPermanentLeave() {
        let leave: NoCodesScreenLeave = NoCodesScreenLifecycle.leave(isBeingDismissed: true, isMovingFromParent: false)

        XCTAssertEqual(leave, .permanent)
    }

    func testMovingFromTheParentIsAPermanentLeave() {
        let leave: NoCodesScreenLeave = NoCodesScreenLifecycle.leave(isBeingDismissed: false, isMovingFromParent: true)

        XCTAssertEqual(leave, .permanent)
    }

    func testBothFlagsTogetherStayAPermanentLeave() {
        let leave: NoCodesScreenLeave = NoCodesScreenLifecycle.leave(isBeingDismissed: true, isMovingFromParent: true)

        XCTAssertEqual(leave, .permanent)
    }

    /// A screen pushed on top hides this one without ending it, so the screen
    /// has to stay loadable and be counted as shown again when it comes back.
    func testMerelyBeingCoveredIsATemporaryLeave() {
        let leave: NoCodesScreenLeave = NoCodesScreenLifecycle.leave(isBeingDismissed: false, isMovingFromParent: false)

        XCTAssertEqual(leave, .temporary)
    }
}

final class NoCodesScreenLoadGateTests: XCTestCase {

    func testALoadThatFinishedInTimeIsApplied() {
        XCTAssertTrue(NoCodesScreenLifecycle.shouldApplyLoadedScreen(isCancelled: false))
    }

    /// A cancelled load belongs to a screen the user already left: reporting it
    /// would fire `noCodesHasShownScreen` after `noCodesFinished`, send a
    /// `screen_shown` event for a screen nobody saw, and render into a detached
    /// web view.
    func testACancelledLoadIsDropped() {
        XCTAssertFalse(NoCodesScreenLifecycle.shouldApplyLoadedScreen(isCancelled: true))
    }
}

final class NoCodesPresentationGateTests: XCTestCase {

    func testACloseWithNothingInFlightAndNothingVisibleHasNothingToActOn() {
        var gate = NoCodesPresentationGate()

        XCTAssertEqual(gate.closeRequested(), [])
    }

    func testAPresentationWithNoInterveningCloseGoesAhead() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(token), .present)
    }

    /// `showScreen` awaits before it has a view controller to hold on to, so a
    /// close arriving inside that window used to hit a nil reference and be
    /// dropped, leaving the screen to appear right after the host closed it.
    func testACloseDuringTheFirstPresentationCancelsItAndReportsTheFlowFinished() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()

        XCTAssertEqual(gate.closeRequested(), [], "there is no screen to close yet")
        // Nothing else will report the flow over, so the cancelled presentation
        // has to: a host gating its UI on that callback waits forever otherwise.
        XCTAssertEqual(gate.presentationReady(token), .cancelled(effects: [.reportFinished]))
    }

    /// A show started while the previous screen is still up raises the same
    /// in-flight state, and a close landing there used to leave that screen on
    /// screen with no dismissal path except a second close.
    func testACloseDuringAPresentationOnTopOfAVisibleScreenAlsoClosesTheVisibleOne() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()
        let second: NoCodesPresentationGate.Token = gate.presentationStarted()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen], "the visible screen stays up otherwise")
        // Dismissing the visible screen reports the flow finished on its own,
        // so the cancelled presentation must not report it a second time.
        XCTAssertEqual(gate.presentationReady(second), .cancelled(effects: []))
    }

    func testADeferredCloseIsConsumedOnceAndDoesNotCancelTheNextPresentation() {
        var gate = NoCodesPresentationGate()
        let cancelled: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.closeRequested()
        XCTAssertEqual(gate.presentationReady(cancelled), .cancelled(effects: [.reportFinished]))

        let next: NoCodesPresentationGate.Token = gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(next), .present)
    }

    func testACloseAfterThePresentationCompletedReachesTheScreen() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(token)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
    }

    /// A show started after the close is a new request from the host, not a
    /// leftover, so it must go ahead.
    func testACloseDoesNotCancelAPresentationStartedAfterIt() {
        var gate = NoCodesPresentationGate()
        let _ = gate.presentationStarted()
        let _ = gate.closeRequested()

        let afterClose: NoCodesPresentationGate.Token = gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(afterClose), .present)
    }

    /// Two `showScreen` calls overlapping one `close`: the close was for the
    /// whole flow, so neither presentation may reach the screen. Consuming it
    /// with whichever presentation resolves first left the other one to present
    /// a screen the host had already closed.
    func testACloseCancelsEveryPresentationThatWasAlreadyInFlight() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let second: NoCodesPresentationGate.Token = gate.presentationStarted()

        XCTAssertEqual(gate.closeRequested(), [], "nothing is on screen yet")

        XCTAssertEqual(gate.presentationReady(first), .cancelled(effects: [.reportFinished]))
        XCTAssertEqual(gate.presentationReady(second), .cancelled(effects: []), "the flow was already reported over")
    }

    /// The same overlap resolved in the other order: whichever presentation
    /// comes back first is the one that reports the flow over, and it is
    /// reported exactly once either way.
    func testTheSecondOfTwoCancelledPresentationsMayResolveFirst() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.closeRequested()

        XCTAssertEqual(gate.presentationReady(second), .cancelled(effects: [.reportFinished]))
        XCTAssertEqual(gate.presentationReady(first), .cancelled(effects: []))
    }

    func testAScreenClosedByAnEarlierCloseIsNotClosedTwice() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(token)
        gate.screenPresented()
        let _ = gate.closeRequested()

        XCTAssertEqual(gate.closeRequested(), [])
    }

    /// The screen can also end on its own — the user taps its close button, or
    /// the flow finishes — and the gate has to hear about it, or a later close
    /// would try to dismiss a screen that is already gone.
    func testAScreenThatFinishedOnItsOwnIsNoLongerTreatedAsVisible() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(token)
        gate.screenPresented()

        XCTAssertEqual(gate.screenFinished(), [.reportFinished])
        XCTAssertEqual(gate.closeRequested(), [])
    }

    func testACancelledPresentationLeavesNoVisibleScreenBehind() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady(token)

        XCTAssertEqual(gate.closeRequested(), [], "the screen never appeared")
    }

    /// The visible screen is dismissed by the same close that cancelled the
    /// presentation, so once that is reconciled nothing is left on screen.
    func testACloseOnTopOfAVisibleScreenLeavesNothingBehindEither() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()
        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady(second)

        XCTAssertEqual(gate.closeRequested(), [])
    }

    func testAScreenPresentedAfterACancelledOneIsClosedNormally() {
        var gate = NoCodesPresentationGate()
        let cancelled: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady(cancelled)

        let next: NoCodesPresentationGate.Token = gate.presentationStarted()
        XCTAssertEqual(gate.presentationReady(next), .present)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
    }
}

// MARK: - Who reports the flow finished

final class NoCodesFinishReportingTests: XCTestCase {

    /// A host that pops or dismisses the screen itself ends the flow just as
    /// the SDK-driven close does; without a finish the coordinator keeps
    /// believing a screen is visible.
    func testAPermanentLeaveEndsTheFlow() {
        XCTAssertTrue(NoCodesScreenLifecycle.reportsFinished(leave: .permanent, hasRemainingFlowScreen: false))
    }

    /// A screen merely covered by another one is still part of a live flow.
    func testATemporaryLeaveDoesNotEndTheFlow() {
        XCTAssertFalse(NoCodesScreenLifecycle.reportsFinished(leave: .temporary, hasRemainingFlowScreen: false))
        XCTAssertFalse(NoCodesScreenLifecycle.reportsFinished(leave: .temporary, hasRemainingFlowScreen: true))
    }

    /// Popping the top screen of a multi-screen flow leaves the one below it on
    /// screen: the flow continues and must not be reported over.
    func testAPermanentLeaveWithAnotherScreenOfTheFlowStillUpDoesNotEndIt() {
        XCTAssertFalse(NoCodesScreenLifecycle.reportsFinished(leave: .permanent, hasRemainingFlowScreen: true))
    }
}
