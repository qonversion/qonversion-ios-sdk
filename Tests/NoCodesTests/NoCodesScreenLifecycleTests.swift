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

    func testACloseWithNothingInFlightIsAppliedImmediately() {
        var gate = NoCodesPresentationGate()

        XCTAssertTrue(gate.closeRequested())
    }

    func testAPresentationWithNoInterveningCloseGoesAhead() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()

        XCTAssertTrue(gate.presentationReady())
    }

    /// `showScreen` awaits before it has a view controller to hold on to, so a
    /// close arriving inside that window used to hit a nil reference and be
    /// dropped, leaving the screen to appear right after the host closed it.
    func testACloseDuringThePresentationIsNotAppliedToAScreenThatDoesNotExistYet() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()

        XCTAssertFalse(gate.closeRequested(), "there is no screen to close yet")
        XCTAssertFalse(gate.presentationReady(), "the host closed the flow before it appeared")
    }

    func testADeferredCloseIsConsumedOnceAndDoesNotCancelTheNextPresentation() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()
        XCTAssertFalse(gate.presentationReady())

        gate.presentationStarted()

        XCTAssertTrue(gate.presentationReady())
    }

    func testACloseAfterThePresentationCompletedReachesTheScreen() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.presentationReady()

        XCTAssertTrue(gate.closeRequested())
    }

    func testAStaleDeferredCloseDoesNotSurviveANewPresentation() {
        var gate = NoCodesPresentationGate()
        gate.presentationStarted()
        let _ = gate.closeRequested()

        // A second show starting before the first one was reconciled must not
        // inherit the pending close.
        gate.presentationStarted()

        XCTAssertTrue(gate.presentationReady())
    }
}
