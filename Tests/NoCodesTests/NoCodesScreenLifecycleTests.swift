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
        gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(), .present)
    }

    /// `showScreen` awaits before it has a view controller to hold on to, so a
    /// close arriving inside that window used to hit a nil reference and be
    /// dropped, leaving the screen to appear right after the host closed it.
    func testACloseDuringTheFirstPresentationCancelsItAndReportsTheFlowFinished() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()

        XCTAssertEqual(gate.closeRequested(), [], "there is no screen to close yet")
        // Nothing else will report the flow over, so the cancelled presentation
        // has to: a host gating its UI on that callback waits forever otherwise.
        XCTAssertEqual(gate.presentationReady(), .cancelled(effects: [.reportFinished]))
    }

    /// A show started while the previous screen is still up raises the same
    /// in-flight state, and a close landing there used to leave that screen on
    /// screen with no dismissal path except a second close.
    func testACloseDuringAPresentationOnTopOfAVisibleScreenAlsoClosesTheVisibleOne() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.screenPresented()
        gate.presentationStarted()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen], "the visible screen stays up otherwise")
        // Dismissing the visible screen reports the flow finished on its own,
        // so the cancelled presentation must not report it a second time.
        XCTAssertEqual(gate.presentationReady(), .cancelled(effects: []))
    }

    func testADeferredCloseIsConsumedOnceAndDoesNotCancelTheNextPresentation() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        XCTAssertEqual(gate.presentationReady(), .cancelled(effects: [.reportFinished]))

        gate.presentationStarted()

        XCTAssertEqual(gate.presentationReady(), .present)
    }

    func testACloseAfterThePresentationCompletedReachesTheScreen() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
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
        gate.screenPresented()
        let _ = gate.closeRequested()

        XCTAssertEqual(gate.closeRequested(), [])
    }

    /// The screen can also end on its own — the user taps its close button, or
    /// the flow finishes — and the gate has to hear about it, or a later close
    /// would try to dismiss a screen that is already gone.
    func testAScreenThatFinishedOnItsOwnIsNoLongerTreatedAsVisible() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.screenPresented()

        XCTAssertEqual(gate.screenFinished(), [.reportFinished])
        XCTAssertEqual(gate.closeRequested(), [])
    }

    func testACancelledPresentationLeavesNoVisibleScreenBehind() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady()

        XCTAssertEqual(gate.closeRequested(), [], "the screen never appeared")
    }

    /// The visible screen is dismissed by the same close that cancelled the
    /// presentation, so once that is reconciled nothing is left on screen.
    func testACloseOnTopOfAVisibleScreenLeavesNothingBehindEither() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()
        gate.screenPresented()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady()

        XCTAssertEqual(gate.closeRequested(), [])
    }

    func testAScreenPresentedAfterACancelledOneIsClosedNormally() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        let _ = gate.presentationReady()

        gate.presentationStarted()
        XCTAssertEqual(gate.presentationReady(), .present)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
    }
}
