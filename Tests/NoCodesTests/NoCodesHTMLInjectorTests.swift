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

    // MARK: - Escaping
    //
    // The locale reaches the injector from the host app and from the screen
    // payload, and the web view it lands in owns the purchase bridge, so a
    // value that can break out of the string literal is code execution.

    func testAQuoteInTheLocaleCannotCloseTheStringLiteral() throws {
        let html = "<html><head></head></html>"
        let hostileLocale = "en\"; window.pwned = true; //"

        let result: String = injector.injectCustomLocale(into: html, locale: hostileLocale)

        // The payload stays one JavaScript token: a single quoted literal whose
        // own quote is escaped, so nothing after it is ever evaluated.
        let literal: String = try extractLiteral(from: result, assignedTo: "window.noCodesCustomLocale")
        XCTAssertEqual(literal, "\"en\\\"; window.pwned = true; \\/\\/\"")
        // The whole assignment is that one literal and nothing else.
        XCTAssertTrue(result.contains("<script>window.noCodesCustomLocale = \(literal);</script>"))
    }

    func testAClosingScriptTagInTheLocaleCannotEndTheScriptElement() {
        let html = "<html><head></head></html>"
        let hostileLocale = "en</script><script>window.pwned = true;</script>"

        let result: String = injector.injectCustomLocale(into: html, locale: hostileLocale)

        // Not a single extra tag boundary: the markup keeps only the one script
        // element the injector opened, so the payload never becomes markup.
        XCTAssertEqual(result.components(separatedBy: "<script").count - 1, 1)
        XCTAssertEqual(result.components(separatedBy: "</script").count - 1, 1)
        XCTAssertFalse(result.contains("<script>window.pwned"))
    }

    func testEscapedLocaleStillDecodesToTheOriginalValue() throws {
        let html = "<html><head></head></html>"
        let hostileLocale = "en</script>\"\n\\"

        let result: String = injector.injectCustomLocale(into: html, locale: hostileLocale)

        // The emitted literal is valid JSON, and parsing it gives back exactly
        // what the caller passed, so the escaping is lossless rather than a
        // sanitizing filter.
        let literal: String = try extractLiteral(from: result, assignedTo: "window.noCodesCustomLocale")
        let data: Data = try XCTUnwrap("[\(literal)]".data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String]
        XCTAssertEqual(decoded?.first, hostileLocale)
    }

    func testControlCharactersInTheLocaleAreEscaped() throws {
        let html = "<html><head></head></html>"
        let hostileLocale = "en\u{2028}\u{0000}"

        let result: String = injector.injectCustomLocale(into: html, locale: hostileLocale)

        let literal: String = try extractLiteral(from: result, assignedTo: "window.noCodesCustomLocale")
        XCTAssertFalse(literal.contains("\u{0000}"))
        let data: Data = try XCTUnwrap("[\(literal)]".data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String]
        XCTAssertEqual(decoded?.first, hostileLocale)
    }

    func testTheThemeValueIsEmittedThroughTheSameEscaping() throws {
        let html = "<html><head></head></html>"

        let result: String = injector.injectTheme(into: html, theme: .dark)

        let literal: String = try extractLiteral(from: result, assignedTo: "window.noCodesTheme")
        XCTAssertEqual(literal, "\"dark\"")
    }

    // MARK: - Private

    /// Pulls the right-hand side of `<name> = <literal>;` out of the injected script.
    private func extractLiteral(from html: String, assignedTo name: String) throws -> String {
        let prefix: String = "\(name) = "
        let start: Range<String.Index> = try XCTUnwrap(html.range(of: prefix))
        let rest: Substring = html[start.upperBound...]
        let end: Range<Substring.Index> = try XCTUnwrap(rest.range(of: ";</script>"))

        return String(rest[..<end.lowerBound])
    }
}
