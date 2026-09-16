import Foundation
import XCTest
import WebKit
@testable import Qonversion

#if !QN_UNIT_TEST_ISOLATION
#error("NoCodes unit tests require UnitIsolation")
#endif

final class QNUnitIsolationNoCodesTransportTests: XCTestCase {
  func testBothNetworkProviderConstructorsDeny() async throws {
    QNUnitIsolationTransport.beginCase(expectedDenials: 2, platformDenials: 0)
    let request = URLRequest(url: URL(string: "http://127.0.0.1:9/nocodes")!)
    for provider in [NetworkProvider(), NetworkProvider(timeout: 1)] {
      do { _ = try await provider.send(request: request); XCTFail("Unmatched request must fail locally") }
      catch { XCTAssertEqual((error as NSError).domain, QNUnitIsolationErrorDomain) }
    }
    XCTAssertTrue(QNUnitIsolationTransport.finishCase())
  }
  func testDefaultImagePreloaderUsesGuardedSession() async {
    QNUnitIsolationTransport.beginCase(expectedDenials: 1, platformDenials: 0)
    let html = "<img src=\"http://127.0.0.1:9/synthetic.png\">"
    let result = await ImagePreloader().preloadImages(in: html)
    XCTAssertEqual(result, html)
    XCTAssertTrue(QNUnitIsolationTransport.finishCase())
  }
}

final class QNUnitIsolationStoreKit2Tests: XCTestCase {
  func testSyncRejectedBeforeTransactionSequence() async throws {
    guard #available(iOS 15.0, *) else { throw XCTSkip("StoreKit2 API unavailable") }
    QNUnitIsolationTransport.beginCase(expectedDenials: 0, platformDenials: 1)
    do { try await StoreKit2Service().syncTransactions(); XCTFail("StoreKit2 must fail locally") }
    catch { XCTAssertEqual((error as NSError).domain, QNUnitIsolationErrorDomain) }
    XCTAssertTrue(QNUnitIsolationTransport.finishCase())
  }
}

final class QNUnitIsolationNoCodesStartupTests: XCTestCase {
  func testSecondaryNoCodesInitializationCannotUseProductionTransport() async throws {
    QNUnitIsolationTransport.beginCase(expectedDenials: 1, platformDenials: 0)
    _ = NoCodes.initialize(with: NoCodesConfiguration(projectKey: "synthetic-unit-key", proxyURL: "http://127.0.0.1:9/"))
    // Startup launches a detached preload task. Observe its denied attempt with a
    // bounded wait; this is not a claim that all future detached work has drained.
    for _ in 0..<60 {
      if QNUnitIsolationTransport.aggregateCounts()["denied"]?.intValue == 1 { break }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertEqual(QNUnitIsolationTransport.aggregateCounts()["denied"]?.intValue, 1)
    XCTAssertTrue(QNUnitIsolationTransport.finishCase())
  }
}

private final class IsolationViewDelegate: NoCodesViewControllerDelegate {
  func noCodesHasShownScreen(id: String) {}
  func noCodesStartsExecuting(action: NoCodesAction) {}
  func noCodesFailedToExecute(action: NoCodesAction, error: Error?) {}
  func noCodesFinishedExecuting(action: NoCodesAction) {}
  func noCodesReceivedCustomAction(value: String) {}
  func noCodesFinished() {}
  func noCodesFailedToLoadScreen(error: Error?) {}
}

final class QNUnitIsolationWebKitTests: XCTestCase {
  @MainActor func testSecondaryViewConstructionDoesNotCreateWebKit() {
    QNUnitIsolationTransport.beginCase(expectedDenials: 0, platformDenials: 1)
    let assembly = NoCodesAssembly(configuration: NoCodesConfiguration(projectKey: "synthetic-unit-key", proxyURL: "http://127.0.0.1:9/"))
    let controller = assembly.viewsAssembly().viewController(withContextKey: "synthetic", delegate: IsolationViewDelegate(), purchaseDelegate: nil, screenCustomizationDelegate: nil, customVariablesDelegate: nil, presentationConfiguration: .defaultConfiguration())
    controller.loadViewIfNeeded()
    controller.view.layoutIfNeeded()
    XCTAssertFalse(controller.view.subviews.contains { $0 is WKWebView })
    XCTAssertTrue(QNUnitIsolationTransport.finishCase())
  }
}
