//
//  NoCodesURLRouterTests.swift
//  NoCodesTests
//
//  How a screen's URL action is opened. The in-app browser takes http(s) only
//  and raises an uncatchable Objective-C exception for anything else, so every
//  string a builder can put on a button has to be routed before it gets there.
//

import XCTest
@testable import NoCodes

final class NoCodesURLRouterTests: XCTestCase {

    func testAWebAddressGoesToTheInAppBrowser() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "https://example.com/terms")

        XCTAssertEqual(route, .inAppBrowser(URL(string: "https://example.com/terms")!))
    }

    func testAPlainHTTPAddressGoesToTheInAppBrowserToo() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "http://example.com")

        XCTAssertEqual(route, .inAppBrowser(URL(string: "http://example.com")!))
    }

    /// The in-app browser matches the scheme literally, so the upper case one
    /// would reach it as unsupported and take the app down.
    func testAnUpperCaseSchemeIsNormalizedForTheInAppBrowser() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "HTTPS://Example.com")

        XCTAssertEqual(route, .inAppBrowser(URL(string: "https://Example.com")!))
    }

    /// A support button configured with a mailto: link used to crash the host
    /// app the moment it was tapped.
    func testAMailtoLinkIsHandedToTheSystem() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "mailto:support@app.com")

        XCTAssertEqual(route, .system(URL(string: "mailto:support@app.com")!))
    }

    func testAnAppStoreLinkIsHandedToTheSystem() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "itms-apps://itunes.apple.com/app/id123")

        XCTAssertEqual(route, .system(URL(string: "itms-apps://itunes.apple.com/app/id123")!))
    }

    func testATelephoneLinkIsHandedToTheSystem() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "tel:+15550100")

        XCTAssertEqual(route, .system(URL(string: "tel:+15550100")!))
    }

    func testACustomAppSchemeIsHandedToTheSystem() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "myapp://settings/billing")

        XCTAssertEqual(route, .system(URL(string: "myapp://settings/billing")!))
    }

    /// `URL(string:)` reads a schemeless string as a relative path and hands it
    /// over happily, so the in-app browser used to get one it raises on.
    func testASchemelessAddressIsUpgradedToHTTPS() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "www.example.com/pricing")

        XCTAssertEqual(route, .inAppBrowser(URL(string: "https://www.example.com/pricing")!))
    }

    func testASchemelessPathHasNowhereToGo() {
        XCTAssertEqual(NoCodesURLRouter.route(urlString: "/pricing"), .unopenable)
    }

    func testProseIsNotAnAddress() {
        XCTAssertEqual(NoCodesURLRouter.route(urlString: "see our website"), .unopenable)
    }

    /// The in-app browser raises on an http(s) URL with nothing behind it just
    /// as it does on a foreign scheme.
    func testAWebSchemeWithoutAHostHasNothingToShow() {
        XCTAssertEqual(NoCodesURLRouter.route(urlString: "http://"), .unopenable)
        XCTAssertEqual(NoCodesURLRouter.route(urlString: "https:///pricing"), .unopenable)
    }

    func testAMissingOrEmptyValueHasNothingToOpen() {
        XCTAssertEqual(NoCodesURLRouter.route(urlString: nil), .unopenable)
        XCTAssertEqual(NoCodesURLRouter.route(urlString: ""), .unopenable)
        XCTAssertEqual(NoCodesURLRouter.route(urlString: "   "), .unopenable)
    }

    func testSurroundingWhitespaceIsNotPartOfTheAddress() {
        let route: NoCodesURLRoute = NoCodesURLRouter.route(urlString: "  https://example.com  ")

        XCTAssertEqual(route, .inAppBrowser(URL(string: "https://example.com")!))
    }
}
