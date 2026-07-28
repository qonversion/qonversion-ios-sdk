//
//  NoCodesPresentationFlowTests.swift
//  NoCodesTests
//
//  The flow decisions the iOS-only coordinator delegates to the gate, and the
//  finish-callback accounting over whole close/show sequences.
//

import XCTest
@testable import NoCodes

// MARK: - Where a screen can be put on screen

final class NoCodesPresentationTargetTests: XCTestCase {

    func testAFullScreenStyleIsPresentedModally() {
        let target: NoCodesPresentationTarget? = NoCodesScreenLifecycle.presentationTarget(style: .fullScreen, hasHost: true, hostHasNavigationController: false, hostIsAlreadyPresenting: false)

        XCTAssertEqual(target, .modal)
    }

    func testAPopoverStyleIsPresentedAsAPopover() {
        let target: NoCodesPresentationTarget? = NoCodesScreenLifecycle.presentationTarget(style: .popover, hasHost: true, hostHasNavigationController: false, hostIsAlreadyPresenting: false)

        XCTAssertEqual(target, .popover)
    }

    func testAPushStyleWithANavigationControllerIsPushed() {
        let target: NoCodesPresentationTarget? = NoCodesScreenLifecycle.presentationTarget(style: .push, hasHost: true, hostHasNavigationController: true, hostIsAlreadyPresenting: false)

        XCTAssertEqual(target, .push)
    }

    /// The coordinator has no host until the delegate hands one over or a
    /// foreground window is found, and neither is guaranteed.
    func testNoHostMeansTheScreenCannotBeShown() {
        for style: NoCodesPresentationStyle in [.fullScreen, .popover, .push] {
            XCTAssertNil(NoCodesScreenLifecycle.presentationTarget(style: style, hasHost: false, hostHasNavigationController: false, hostIsAlreadyPresenting: false))
        }
    }

    /// `pushViewController` on a nil navigation controller is a silent no-op:
    /// the screen would never appear and the host would wait for a flow that
    /// never finishes.
    func testAPushWithoutANavigationControllerCannotBeShown() {
        XCTAssertNil(NoCodesScreenLifecycle.presentationTarget(style: .push, hasHost: true, hostHasNavigationController: false, hostIsAlreadyPresenting: false))
    }

    /// UIKit refuses to present on a controller that is already presenting and
    /// only logs about it, which is the same never-appearing screen.
    func testAHostThatIsAlreadyPresentingCannotShowAModalScreen() {
        XCTAssertNil(NoCodesScreenLifecycle.presentationTarget(style: .fullScreen, hasHost: true, hostHasNavigationController: false, hostIsAlreadyPresenting: true))
        XCTAssertNil(NoCodesScreenLifecycle.presentationTarget(style: .popover, hasHost: true, hostHasNavigationController: false, hostIsAlreadyPresenting: true))
    }

    /// A push goes into the navigation stack, not on top of the presentation,
    /// so a modal already up does not stand in its way.
    func testAHostThatIsAlreadyPresentingCanStillPush() {
        let target: NoCodesPresentationTarget? = NoCodesScreenLifecycle.presentationTarget(style: .push, hasHost: true, hostHasNavigationController: true, hostIsAlreadyPresenting: true)

        XCTAssertEqual(target, .push)
    }
}

// MARK: - A presentation that never reached the screen

final class NoCodesUnpresentableScreenTests: XCTestCase {

    /// The coordinator resolves the controller it presents on only after the
    /// gate has already been asked whether it may present. When nothing can put
    /// the screen on screen the gate must not think a screen is up: a close
    /// would otherwise dismiss a view controller that was never presented, and
    /// its dismissal completion — the only thing that reports the flow finished
    /// on that route — would never fire.
    func testAPresentationThatNeverReachedTheScreenLeavesNothingToClose() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        XCTAssertEqual(gate.presentationReady(token), .present)

        // No `screenPresented()`: the coordinator bailed out before presenting.
        XCTAssertEqual(gate.closeRequested(), [])
    }

    /// Nothing else will speak for a screen that never appeared, so the host
    /// hears both why it did not and that the flow is over — a host gating its
    /// own UI on the finish callback waits forever otherwise.
    func testAnUnpresentableScreenIsReportedAndEndsTheFlow() {
        var gate = NoCodesPresentationGate()
        let token: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(token)

        XCTAssertEqual(gate.presentationUnavailable(), [.reportFailedToPresent, .reportFinished])
    }

    /// A second screen that fails to appear leaves the first one up, so the
    /// flow is not over and must not be reported as such.
    func testAnUnpresentableScreenOnTopOfAVisibleOneDoesNotEndTheFlow() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()

        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(second)

        XCTAssertEqual(gate.presentationUnavailable(), [.reportFailedToPresent])
    }

    /// The screen that could not appear is not the screen the user is looking
    /// at, so closing still has to reach the visible one.
    func testTheVisibleScreenSurvivesAnUnpresentableOneOnTop() {
        var gate = NoCodesPresentationGate()
        let first: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(first)
        gate.screenPresented()

        let second: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(second)
        let _ = gate.presentationUnavailable()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
    }

    func testAScreenPresentedAfterAnUnpresentableOneIsClosedNormally() {
        var gate = NoCodesPresentationGate()
        let failed: NoCodesPresentationGate.Token = gate.presentationStarted()
        let _ = gate.presentationReady(failed)
        let _ = gate.presentationUnavailable()

        let next: NoCodesPresentationGate.Token = gate.presentationStarted()
        XCTAssertEqual(gate.presentationReady(next), .present)
        gate.screenPresented()

        XCTAssertEqual(gate.closeRequested(), [.dismissVisibleScreen])
    }
}

// MARK: - Exactly one finish per flow

/// Every host callback the flow can produce is an effect the gate hands back,
/// so a whole close/show sequence can be traced without a view hierarchy.
///
/// The one thing that is not a gate decision is the dismissal itself: the
/// coordinator turns `dismissVisibleScreen` into `NoCodesViewController.close()`,
/// whose two routes — a dismissal completion for a presented screen, a
/// synchronous call for a pushed one — both come back as `screenFinished()`.
/// `dismiss(visibleScreen:)` below stands for that round trip.
private struct FlowTrace {

    private(set) var effects: [NoCodesFlowEffect] = []
    private var gate = NoCodesPresentationGate()

    var finishCount: Int {
        return effects.filter { $0 == .reportFinished }.count
    }

    mutating func showStarted() -> NoCodesPresentationGate.Token {
        return gate.presentationStarted()
    }

    /// Returns whether the screen went up.
    @discardableResult
    mutating func showReady(_ token: NoCodesPresentationGate.Token, canPresent: Bool = true) -> Bool {
        let outcome: NoCodesPresentationOutcome = gate.presentationReady(token)

        guard case .present = outcome else {
            if case let .cancelled(cancellationEffects) = outcome {
                effects += cancellationEffects
            }

            return false
        }

        guard canPresent else {
            effects += gate.presentationUnavailable()

            return false
        }

        gate.screenPresented()

        return true
    }

    mutating func close() {
        let closeEffects: [NoCodesFlowEffect] = gate.closeRequested()
        effects += closeEffects

        if closeEffects.contains(.dismissVisibleScreen) {
            dismissVisibleScreen()
        }
    }

    /// The dismissal the coordinator asked for came back from the view
    /// controller.
    mutating func dismissVisibleScreen() {
        effects += gate.screenFinished()
    }
}

final class NoCodesFinishCallbackTests: XCTestCase {

    /// (a) close with a visible screen and nothing in flight.
    func testAVisibleScreenReportsTheFlowFinishedExactlyOnce() {
        var trace = FlowTrace()
        let token: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(token))

        trace.close()

        XCTAssertEqual(trace.effects, [.dismissVisibleScreen, .reportFinished])
        XCTAssertEqual(trace.finishCount, 1)
    }

    /// (b) close with a visible screen and a show in flight: the dismissal
    /// reports the flow finished, the cancelled presentation stays quiet.
    func testAVisibleScreenAndAShowInFlightStillReportFinishedOnlyOnce() {
        var trace = FlowTrace()
        let first: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(first))
        let second: NoCodesPresentationGate.Token = trace.showStarted()

        trace.close()
        XCTAssertFalse(trace.showReady(second), "the presentation was cancelled")

        XCTAssertEqual(trace.effects, [.dismissVisibleScreen, .reportFinished])
        XCTAssertEqual(trace.finishCount, 1)
    }

    /// (c) close with only a show in flight: nothing is on screen to dismiss,
    /// so the cancelled presentation is the only thing that can speak.
    func testAShowInFlightAloneReportsTheFlowFinishedWhenItIsCancelled() {
        var trace = FlowTrace()
        let token: NoCodesPresentationGate.Token = trace.showStarted()

        trace.close()
        XCTAssertFalse(trace.showReady(token))

        XCTAssertEqual(trace.effects, [.reportFinished])
        XCTAssertEqual(trace.finishCount, 1)
    }

    /// (d) close with nothing going on: there is no flow to finish, and
    /// inventing a callback would tell a host its screen closed when it never
    /// asked for one.
    func testACloseWithNothingGoingOnReportsNothing() {
        var trace = FlowTrace()

        trace.close()

        XCTAssertEqual(trace.effects, [])
        XCTAssertEqual(trace.finishCount, 0)
    }

    /// (e) the show that could not be presented at all.
    func testAScreenThatCouldNotBePresentedReportsTheFlowFinishedExactlyOnce() {
        var trace = FlowTrace()
        let token: NoCodesPresentationGate.Token = trace.showStarted()

        XCTAssertFalse(trace.showReady(token, canPresent: false))

        XCTAssertEqual(trace.effects, [.reportFailedToPresent, .reportFinished])
        XCTAssertEqual(trace.finishCount, 1)
    }

    /// (f) a close for a screen that never made it on screen has nothing to
    /// dismiss, and the failed presentation already reported the flow over.
    func testAClosingAfterAnUnpresentableScreenAddsNoSecondFinish() {
        var trace = FlowTrace()
        let token: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertFalse(trace.showReady(token, canPresent: false))

        trace.close()

        XCTAssertEqual(trace.finishCount, 1)
    }

    /// (g) the screen ending on its own — the user taps its close button — is
    /// the same single finish, and a close arriving afterwards adds none.
    func testAScreenThatEndedOnItsOwnReportsTheFlowFinishedExactlyOnce() {
        var trace = FlowTrace()
        let token: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(token))

        trace.dismissVisibleScreen()
        trace.close()

        XCTAssertEqual(trace.effects, [.reportFinished])
        XCTAssertEqual(trace.finishCount, 1)
    }

    /// (h) the host pops or dismisses the screen itself, without ever calling
    /// `close()`. The screen still reports the flow over, exactly once, or the
    /// coordinator keeps believing a screen is visible.
    func testAHostDrivenDismissalReportsTheFlowFinishedExactlyOnce() {
        var trace = FlowTrace()
        let token: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(token))

        // The permanent leave the view controller detects in viewDidDisappear.
        trace.dismissVisibleScreen()

        XCTAssertEqual(trace.effects, [.reportFinished])
        XCTAssertEqual(trace.finishCount, 1)

        // A show started afterwards is a new flow with its own finish.
        let next: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(next))
        trace.close()

        XCTAssertEqual(trace.finishCount, 2)
    }

    /// (i) two overlapping shows and a single close: the close ends the flow,
    /// so neither presentation may reach the screen and the flow is reported
    /// over exactly once.
    func testTwoOverlappingShowsAndOneCloseReportTheFlowFinishedExactlyOnce() {
        var trace = FlowTrace()
        let first: NoCodesPresentationGate.Token = trace.showStarted()
        let second: NoCodesPresentationGate.Token = trace.showStarted()

        trace.close()

        XCTAssertFalse(trace.showReady(first), "the host closed the flow")
        XCTAssertFalse(trace.showReady(second), "the second presentation was cancelled by the same close")
        XCTAssertEqual(trace.effects, [.reportFinished])
        XCTAssertEqual(trace.finishCount, 1)
    }

    /// Two screens in a row are two flows, so two finishes.
    func testTwoScreensInARowReportTheFlowFinishedOncePerScreen() {
        var trace = FlowTrace()
        let first: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(first))
        trace.close()

        let second: NoCodesPresentationGate.Token = trace.showStarted()
        XCTAssertTrue(trace.showReady(second))
        trace.close()

        XCTAssertEqual(trace.finishCount, 2)
    }
}
