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

// MARK: - The screen_shown / screen_closed pair

final class NoCodesScreenSessionTests: XCTestCase {

    func testAScreenThatAppearedOwesAShownEvent() {
        var session = NoCodesScreenSession()

        XCTAssertTrue(session.trackShown())
    }

    /// `viewDidAppear` and the finished load both announce the screen, and the
    /// backend must not count it twice.
    func testAScreenAlreadyCountedAsShownIsNotCountedAgain() {
        var session = NoCodesScreenSession()
        XCTAssertTrue(session.trackShown())

        XCTAssertFalse(session.trackShown())
    }

    func testAShownScreenOwesAClosedEvent() {
        var session = NoCodesScreenSession()
        let _ = session.trackShown()

        XCTAssertTrue(session.trackClosed())
    }

    /// A screen leaves by several routes at once — the deliberate close, then
    /// `viewDidDisappear`, then `deinit` — and each of them asks.
    func testTheSeveralRoutesOutOfAScreenProduceOneClosedEvent() {
        var session = NoCodesScreenSession()
        let _ = session.trackShown()
        XCTAssertTrue(session.trackClosed())

        XCTAssertFalse(session.trackClosed(), "viewDidDisappear after the deliberate close")
        XCTAssertFalse(session.trackClosed(), "deinit")
    }

    /// A screen whose load never finished has no screen id and was never
    /// counted as shown, so there is no viewing session to close.
    func testAScreenThatWasNeverShownOwesNoClosedEvent() {
        var session = NoCodesScreenSession()

        XCTAssertFalse(session.trackClosed())
    }

    /// A screen covered by another one of the same flow closes its session
    /// right away: UIKit sends it no second `viewDidDisappear`, so waiting for
    /// one left the event to `deinit`, after the flow had already flushed.
    /// Coming back opens a fresh session that owes its own pair.
    func testACoveredScreenClosesItsSessionAndOpensANewOneWhenItComesBack() {
        var session = NoCodesScreenSession()
        let _ = session.trackShown()

        XCTAssertTrue(session.trackClosed(), "covered by the screen pushed on top")
        XCTAssertTrue(session.trackShown(), "back on screen after that one popped")
        XCTAssertTrue(session.trackClosed(), "the flow ended")
    }

    /// The `deinit` fallback must not add a second event for a screen that
    /// already closed its session when it was covered.
    func testACoveredScreenThatNeverCameBackIsNotClosedTwice() {
        var session = NoCodesScreenSession()
        let _ = session.trackShown()
        let _ = session.trackClosed()

        XCTAssertFalse(session.trackClosed(), "deinit, with the flow long gone")
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

    /// A second `showScreen` on top of a visible one stacks on it. The close
    /// has to reach both, and the flow is over only once the second of them
    /// reported back — reporting after the first left an SDK screen on screen
    /// behind a flow the host had already been told was finished.
    func testAStackOfScreensIsOnlyFinishedWhenTheLastOneReported() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()
        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(second)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
        XCTAssertEqual(gate.screenFinished(), [], "the screen underneath is still up")
        XCTAssertEqual(gate.screenFinished(), [.reportFinished])
    }

    /// A flow that pushed screens of its own has more screens reporting than
    /// the coordinator ever presented: the dismissal takes the whole navigation
    /// stack, and every screen in it announces the flow over.
    func testAScreenReportingAfterTheFlowEndedIsAnEchoTheHostDoesNotHear() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(token)
        gate.screenPresented()
        let _ = gate.closeRequested()

        XCTAssertEqual(gate.screenFinished(), [.reportFinished])
        XCTAssertEqual(gate.screenFinished(), [], "the screen the flow pushed on top")
    }

    /// A second close while the first one is still tearing the stack down has
    /// nothing left to ask for, but once the flow ended a later one starts over.
    func testACloseIsOnlyActedOnOncePerFlow() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()
        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(second)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
        XCTAssertEqual(gate.closeRequested(), [], "the first close already reached both screens")

        let _ = gate.screenFinished()
        let _ = gate.screenFinished()

        let next: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(next)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen], "a new flow closes normally")
    }

    /// The coordinator went looking for the screens to dismiss and found none
    /// left. Nothing will report back, so the report comes from the gate.
    func testACloseWithTheScreensAlreadyGoneStillEndsTheFlow() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(token)
        gate.screenPresented()
        let _ = gate.closeRequested()

        XCTAssertEqual(gate.nothingToDismiss(), [.reportFinished])
        XCTAssertEqual(gate.screenFinished(), [], "no screen is left to report")
    }

    /// A screen shown while the previous dismissal is still animating is not a
    /// screen the earlier close could have reached, so it has to stay closable.
    func testAScreenShownRightAfterACloseIsStillClosable() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()
        let _ = gate.closeRequested()

        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(second)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
    }

    func testNothingToDismissWithNoFlowRunningReportsNothing() {
        var gate = NoCodesPresentationGate()

        XCTAssertEqual(gate.nothingToDismiss(), [])
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

// MARK: - What the host hears about one action

final class NoCodesActionReportingTests: XCTestCase {

    /// The actions the screen runtime uses to talk to the SDK are plumbing, not
    /// work the host asked about.
    func testTheRuntimesOwnActionsAreNotAnnouncedToTheHost() {
        for actionType: NoCodesActionType in [.loadProducts, .screenAnalytics, .getContext, .purchaseLoaderPresent, .showScreen] {
            XCTAssertFalse(NoCodesScreenLifecycle.announcesExecution(actionType: actionType))
        }
    }

    func testEveryActionTheHostCanActOnIsAnnounced() {
        for actionType: NoCodesActionType in [.url, .deeplink, .navigation, .purchase, .restore, .close, .closeAll, .redeemPromoCode, .custom] {
            XCTAssertTrue(NoCodesScreenLifecycle.announcesExecution(actionType: actionType))
        }
    }

    /// A payload the SDK cannot read is still an action the host was told about,
    /// so it owes an outcome rather than nothing at all.
    func testAnUnknownActionIsAnnouncedAndThereforeOwesAnOutcome() {
        XCTAssertTrue(NoCodesScreenLifecycle.announcesExecution(actionType: .unknown))
    }

    /// A screen that renders its own purchase loader only takes it down when a
    /// failure event arrives, so a purchase the SDK could not start has to
    /// reach the screen as well as the host.
    func testAFailedPurchaseIsReportedToTheScreenAsWellAsTheHost() {
        XCTAssertEqual(NoCodesScreenLifecycle.failureReport(actionType: .purchase), .hostAndScreen)
    }

    func testEveryOtherFailedActionIsReportedToTheHostAlone() {
        for actionType: NoCodesActionType in [.url, .deeplink, .navigation, .unknown, .custom] {
            XCTAssertEqual(NoCodesScreenLifecycle.failureReport(actionType: actionType), .host)
        }
    }
}

// MARK: - Where a follow-up screen can go

final class NoCodesFollowUpScreenTests: XCTestCase {

    func testAScreenInANavigationStackCanPushTheNextOne() {
        XCTAssertTrue(NoCodesScreenLifecycle.canPushFollowUpScreen(hasNavigationController: true))
    }

    /// A screen presented as a popover is presented on its own, without the
    /// navigation controller the modal route wraps it in. `pushViewController`
    /// on `nil` is a silent no-op the host used to hear about as a success.
    func testAPopoverScreenCannotPushAFollowUpScreen() {
        XCTAssertFalse(NoCodesScreenLifecycle.canPushFollowUpScreen(hasNavigationController: false))
    }
}
