//
//  NoCodesHTMLInjectorTests.swift
//  NoCodesTests
//
//  Where the locale and theme bootstrap scripts land in the screen markup.
//

import XCTest
@testable import NoCodes

final class NoCodesHTMLInjectorTests: XCTestCase {

    private var injector: NoCodesHTMLInjector!

    override func setUp() {
        super.setUp()
        injector = NoCodesHTMLInjector()
    }

    override func tearDown() {
        injector = nil
        super.tearDown()
    }

    // MARK: - Locale

    func testLocaleScriptIsInsertedRightAfterTheHeadTag() {
        let html = "<html><head><title>t</title></head><body></body></html>"

        let result: String = injector.injectCustomLocale(into: html, locale: "de-DE")

        XCTAssertEqual(result, "<html><head><script>window.noCodesCustomLocale = \"de-DE\";</script><title>t</title></head><body></body></html>")
    }

    func testHeadTagIsMatchedCaseInsensitively() {
        let html = "<html><HEAD><title>t</title></HEAD></html>"

        let result: String = injector.injectCustomLocale(into: html, locale: "en")

        XCTAssertEqual(result, "<html><HEAD><script>window.noCodesCustomLocale = \"en\";</script><title>t</title></HEAD></html>")
    }

    func testScriptIsPrependedWhenTheMarkupHasNoHead() {
        let html = "<div>bare fragment</div>"

        let result: String = injector.injectCustomLocale(into: html, locale: "fr")

        XCTAssertEqual(result, "<script>window.noCodesCustomLocale = \"fr\";</script><div>bare fragment</div>")
    }

    func testNoLocaleLeavesTheMarkupUntouched() {
        let html = "<html><head></head></html>"

        let result: String = injector.injectCustomLocale(into: html, locale: nil)

        XCTAssertEqual(result, html)
    }

    func testOnlyTheFirstHeadOccurrenceReceivesTheScript() {
        let html = "<html><head></head><body><head>nested</head></body></html>"

        let result: String = injector.injectCustomLocale(into: html, locale: "en")

        let occurrences: Int = result.components(separatedBy: "noCodesCustomLocale").count - 1
        XCTAssertEqual(occurrences, 1)
        XCTAssertTrue(result.hasPrefix("<html><head><script>"))
    }

    // MARK: - Theme

    func testThemeScriptCarriesTheRawThemeValue() {
        let html = "<html><head></head></html>"

        let light: String = injector.injectTheme(into: html, theme: .light)
        let dark: String = injector.injectTheme(into: html, theme: .dark)
        let auto: String = injector.injectTheme(into: html, theme: .auto)

        XCTAssertTrue(light.contains("window.noCodesTheme = \"light\";"))
        XCTAssertTrue(dark.contains("window.noCodesTheme = \"dark\";"))
        XCTAssertTrue(auto.contains("window.noCodesTheme = \"auto\";"))
    }

    func testThemeAndLocaleCanBothBeInjected() {
        let html = "<html><head></head><body></body></html>"

        let withLocale: String = injector.injectCustomLocale(into: html, locale: "es")
        let result: String = injector.injectTheme(into: withLocale, theme: .dark)

        XCTAssertTrue(result.contains("noCodesCustomLocale"))
        XCTAssertTrue(result.contains("noCodesTheme"))
        // Both scripts stay inside the head.
        let headEnd: Range<String.Index> = try! XCTUnwrap(result.range(of: "</head>"))
        let localePosition: Range<String.Index> = try! XCTUnwrap(result.range(of: "noCodesCustomLocale"))
        let themePosition: Range<String.Index> = try! XCTUnwrap(result.range(of: "noCodesTheme"))
        XCTAssertTrue(localePosition.lowerBound < headEnd.lowerBound)
        XCTAssertTrue(themePosition.lowerBound < headEnd.lowerBound)
    }

    func testThemeScriptIsPrependedWhenTheMarkupHasNoHead() {
        let html = "<div>bare fragment</div>"

        let result: String = injector.injectTheme(into: html, theme: .light)

        XCTAssertTrue(result.hasPrefix("<script>window.noCodesTheme = \"light\";</script>"))
    }
}
