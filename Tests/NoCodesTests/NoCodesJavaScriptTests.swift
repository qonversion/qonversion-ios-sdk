//
//  NoCodesJavaScriptTests.swift
//  NoCodesTests
//
//  Turning host and server supplied values into JavaScript the screen can run.
//

import XCTest
import JavaScriptCore
@testable import NoCodes

final class NoCodesJavaScriptLiteralTests: XCTestCase {

    func testAPlainValueBecomesAQuotedLiteral() {
        XCTAssertEqual(NoCodesJavaScript.stringLiteral(from: "de-DE"), "\"de-DE\"")
    }

    func testAnEmptyValueBecomesAnEmptyLiteral() {
        XCTAssertEqual(NoCodesJavaScript.stringLiteral(from: ""), "\"\"")
    }

    /// A raw newline inside a JavaScript string literal is a syntax error, and
    /// it takes down every statement evaluated alongside it.
    func testANewlineNeverReachesTheLiteralRaw() throws {
        let value = "first\nsecond\r\nthird"

        let literal: String = NoCodesJavaScript.stringLiteral(from: value)

        XCTAssertFalse(literal.contains("\n"))
        XCTAssertFalse(literal.contains("\r"))
        XCTAssertEqual(literal.components(separatedBy: "\n").count, 1, "the literal has to stay on one line")
        XCTAssertEqual(try evaluate(literal: literal), value)
    }

    func testTheLineSeparatorsAJavaScriptLiteralCannotCarryAreEscaped() throws {
        let value = "a\u{2028}b\u{2029}c"

        let literal: String = NoCodesJavaScript.stringLiteral(from: value)

        XCTAssertFalse(literal.contains("\u{2028}"))
        XCTAssertFalse(literal.contains("\u{2029}"))
        XCTAssertEqual(try evaluate(literal: literal), value)
    }

    func testQuotesAndBackslashesSurviveIntact() throws {
        let value = "a\"b\\c\\\"d"

        let literal: String = NoCodesJavaScript.stringLiteral(from: value)

        XCTAssertEqual(try evaluate(literal: literal), value)
    }

    func testTabsAndControlCharactersSurviveIntact() throws {
        let value = "a\tb\u{0000}c"

        let literal: String = NoCodesJavaScript.stringLiteral(from: value)

        XCTAssertEqual(try evaluate(literal: literal), value)
    }

    // MARK: - Private

    /// Runs the literal through a real JavaScript engine, which is the only
    /// honest way to tell a valid literal from a plausible looking string.
    private func evaluate(literal: String) throws -> String? {
        let context: JSContext = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in
            XCTFail("the literal is not valid JavaScript: \(exception?.toString() ?? "unknown")")
        }

        let value: JSValue? = context.evaluateScript("var result = \(literal); result;")

        return value?.toString()
    }
}

final class NoCodesThemeUpdateScriptTests: XCTestCase {

    func testTheScriptCarriesTheResolvedThemeAndAnnouncesTheUpdate() {
        let script: String = NoCodesJavaScript.themeUpdateScript(resolvedTheme: .dark)

        XCTAssertTrue(script.contains("window.noCodesContext.device.theme = \"dark\";"))
        XCTAssertTrue(script.contains("window.dispatchEvent(new Event(\"noCodesContextUpdate\"));"))
    }

    func testTheLightThemeIsCarriedTheSameWay() {
        let script: String = NoCodesJavaScript.themeUpdateScript(resolvedTheme: .light)

        XCTAssertTrue(script.contains("window.noCodesContext.device.theme = \"light\";"))
    }
}

final class NoCodesCustomVariablesScriptTests: XCTestCase {

    func testNoVariablesProduceNoScript() {
        XCTAssertEqual(NoCodesJavaScript.setCustomVariablesScript(for: [:]), "")
    }

    func testASingleVariableBecomesOneSetterCall() {
        let variables: [String: String] = ["plan": "gold"]

        let script: String = NoCodesJavaScript.setCustomVariablesScript(for: variables)

        XCTAssertEqual(script, "window.noCodesSetVariable?.(\"plan\", \"gold\");")
    }

    func testTheVariablesAreEmittedInAStableOrder() {
        let variables: [String: String] = ["c": "3", "a": "1", "b": "2"]

        let script: String = NoCodesJavaScript.setCustomVariablesScript(for: variables)

        let names: [String] = script.components(separatedBy: "\n").compactMap { line in
            return line.components(separatedBy: "\"").dropFirst().first
        }
        XCTAssertEqual(names, ["a", "b", "c"])
    }

    /// One statement per line only holds if no value can smuggle a newline in,
    /// which is exactly what the old hand rolled escaping allowed.
    func testAValueCarryingNewlinesStaysOnItsOwnLine() {
        let variables: [String: String] = ["a": "one\ntwo", "b": "three\nfour"]

        let script: String = NoCodesJavaScript.setCustomVariablesScript(for: variables)

        XCTAssertEqual(script.components(separatedBy: "\n").count, 2)
    }

    func testTheHostsVariablesReachTheScreenExactlyAsGiven() throws {
        let variables: [String: String] = [
            "plain": "gold",
            "with\"quote": "va\"lue",
            "with\nnewline": "line one\nline two",
            "with\\backslash": "back\\slash",
            "with</script>": "a</script>b",
            "withSeparator": "a\u{2028}b"
        ]

        let script: String = NoCodesJavaScript.setCustomVariablesScript(for: variables)

        // Run it against a stub of the bridge the screen exposes: the values
        // have to arrive as the host passed them, and nothing may fail to parse.
        let received: [String: String] = try evaluate(script: script)
        XCTAssertEqual(received, variables)
    }

    func testAHostileVariableCannotAddStatementsOfItsOwn() throws {
        let variables: [String: String] = ["plan": "\"); window.pwned = true; //"]

        let script: String = NoCodesJavaScript.setCustomVariablesScript(for: variables)

        let context: JSContext = try makeContext()
        context.evaluateScript(script)

        let pwned: JSValue? = context.evaluateScript("window.pwned")
        XCTAssertTrue(pwned?.isUndefined ?? false, "the payload executed as code")
        let received: [String: String] = try readVariables(from: context)
        XCTAssertEqual(received, variables)
    }

    // MARK: - Private

    private func evaluate(script: String) throws -> [String: String] {
        let context: JSContext = try makeContext()
        context.evaluateScript(script)

        return try readVariables(from: context)
    }

    private func makeContext() throws -> JSContext {
        let context: JSContext = try XCTUnwrap(JSContext())
        // Stays installed for everything the test evaluates afterwards, so a
        // script that does not parse fails the test rather than silently
        // setting nothing.
        context.exceptionHandler = { _, exception in
            XCTFail("the generated script is not valid JavaScript: \(exception?.toString() ?? "unknown")")
        }

        // The screen exposes noCodesSetVariable on window; record what it gets.
        context.evaluateScript("""
        var window = {};
        window.received = {};
        window.noCodesSetVariable = function(name, value) { window.received[name] = value; };
        """)

        return context
    }

    private func readVariables(from context: JSContext) throws -> [String: String] {
        let value: JSValue = try XCTUnwrap(context.evaluateScript("window.received"))
        let received: [String: String] = try XCTUnwrap(value.toDictionary() as? [String: String])

        return received
    }
}
