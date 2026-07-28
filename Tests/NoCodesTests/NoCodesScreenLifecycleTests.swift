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

        let outcome: NoCodesCloseOutcome = gate.closeRequested()

        XCTAssertFalse(outcome.closesVisibleScreen)
        XCTAssertFalse(outcome.cancelsPendingPresentation)
    }

    func testAPresentationWithNoInterveningCloseGoesAhead() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(), .present)
    }

    /// `showScreen` awaits before it has a view controller to hold on to, so a
    /// close arriving inside that window used to hit a nil reference and be
    /// dropped, leaving the screen to appear right after the host closed it.
    func testACloseDuringTheFirstPresentationCancelsItAndReportsTheFlowFinished() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()

        let outcome: NoCodesCloseOutcome = gate.closeRequested()

        XCTAssertFalse(outcome.closesVisibleScreen, "there is no screen to close yet")
        XCTAssertTrue(outcome.cancelsPendingPresentation)
        // Nothing else will report the flow over, so the cancelled presentation
        // has to: a host gating its UI on that callback waits forever otherwise.
        XCTAssertEqual(gate.presentationReady(), .cancelled(reportsFinished: true))
    }

    /// A show started while the previous screen is still up raises the same
    /// in-flight state, and a close landing there used to leave that screen on
    /// screen with no dismissal path except a second close.
    func testACloseDuringAPresentationOnTopOfAVisibleScreenAlsoClosesTheVisibleOne() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.presentationStarted()

        let outcome: NoCodesCloseOutcome = gate.closeRequested()

        XCTAssertTrue(outcome.closesVisibleScreen, "the visible screen stays up otherwise")
        XCTAssertTrue(outcome.cancelsPendingPresentation)
        // Dismissing the visible screen reports the flow finished on its own,
        // so the cancelled presentation must not report it a second time.
        XCTAssertEqual(gate.presentationReady(), .cancelled(reportsFinished: false))
    }

    func testADeferredCloseIsConsumedOnceAndDoesNotCancelTheNextPresentation() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        XCTAssertEqual(gate.presentationReady(), .cancelled(reportsFinished: true))

        gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(), .present)
    }

    func testACloseAfterThePresentationCompletedReachesTheScreen() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()

        let outcome: NoCodesCloseOutcome = gate.closeRequested()

        XCTAssertTrue(outcome.closesVisibleScreen)
        XCTAssertFalse(outcome.cancelsPendingPresentation)
    }

    func testAStaleDeferredCloseDoesNotSurviveANewPresentation() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()

        // A second show starting before the first one was reconciled must not
        // inherit the pending close.
        gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(), .present)
    }

    func testAScreenClosedByAnEarlierCloseIsNotClosedTwice() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        let _ = gate.closeRequested()

        let outcome: NoCodesCloseOutcome = gate.closeRequested()

        XCTAssertFalse(outcome.closesVisibleScreen)
        XCTAssertFalse(outcome.cancelsPendingPresentation)
    }

    /// The screen can also end on its own — the user taps its close button, or
    /// the flow finishes — and the gate has to hear about it, or a later close
    /// would try to dismiss a screen that is already gone.
    func testAScreenThatFinishedOnItsOwnIsNoLongerTreatedAsVisible() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.screenFinished()

        XCTAssertFalse(gate.closeRequested().closesVisibleScreen)
    }

    func testACancelledPresentationLeavesNoVisibleScreenBehind() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady()

        XCTAssertFalse(gate.closeRequested().closesVisibleScreen, "the screen never appeared")
    }

    /// The visible screen is dismissed by the same close that cancelled the
    /// presentation, so once that is reconciled nothing is left on screen.
    func testACloseOnTopOfAVisibleScreenLeavesNothingBehindEither() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady()

        let outcome: NoCodesCloseOutcome = gate.closeRequested()

        XCTAssertFalse(outcome.closesVisibleScreen)
        XCTAssertFalse(outcome.cancelsPendingPresentation)
    }

    func testAScreenPresentedAfterACancelledOneIsClosedNormally() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady()

        gate.presentationStarted()
        XCTAssertEqual(gate.presentationReady(), .present)

        XCTAssertTrue(gate.closeRequested().closesVisibleScreen)
    }
}
