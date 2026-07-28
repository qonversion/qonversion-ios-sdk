//
//  NoCodesScreenDecodingTests.swift
//  NoCodesTests
//

import XCTest
@testable import NoCodes

final class NoCodesScreenDecodingTests: XCTestCase {

    func testDecodesScreenFromContextKeyArrayResponse() throws {
        let json = """
        [{"id": "screen-1", "body": "<html>hi</html>", "context_key": "main"}]
        """
        let data: Data = Data(json.utf8)
        let decoder = JSONDecoder()

        let screen: NoCodesScreen = try decoder.decode(NoCodesScreen.self, from: data)

        XCTAssertEqual(screen.id, "screen-1")
        XCTAssertEqual(screen.contextKey, "main")
        XCTAssertTrue(screen.defaultVariables.isEmpty)
    }

    func testDecodesScreenFromSingleObjectResponse() throws {
        let json = """
        {"id": "screen-2", "body": "<html>bye</html>", "context_key": "paywall"}
        """
        let data: Data = Data(json.utf8)
        let decoder = JSONDecoder()

        let screen: NoCodesScreen = try decoder.decode(NoCodesScreen.self, from: data)

        XCTAssertEqual(screen.id, "screen-2")
        XCTAssertEqual(screen.contextKey, "paywall")
    }

    func testDecodesVariablesToleratingUnknownAndMissingKinds() throws {
        let json = """
        {
          "id": "screen-3",
          "body": "<html></html>",
          "context_key": "onboarding",
          "variables": [
            {"key": "legacy", "type": "string", "value": "old"},
            {"kind": "custom", "key": "flag", "type": "boolean", "value": true},
            {"kind": "selected_product", "key": "default_selected_product", "type": "string", "value": "annual"},
            {"kind": "brand_new_kind", "key": "future", "type": "number", "value": 34}
          ]
        }
        """
        let data: Data = Data(json.utf8)
        let decoder = JSONDecoder()

        let screen: NoCodesScreen = try decoder.decode(NoCodesScreen.self, from: data)

        XCTAssertEqual(screen.defaultVariables.count, 4)
        // A payload predating the `kind` field carries authored custom variables.
        XCTAssertEqual(screen.defaultVariable(forKey: "legacy")?.kind, .custom)
        XCTAssertEqual(screen.defaultVariable(forKey: "flag")?.value, .bool(true))
        XCTAssertEqual(screen.defaultSelectedProductId, "annual")
        // A kind added on the backend later must not fail the whole decode.
        XCTAssertEqual(screen.defaultVariable(forKey: "future")?.kind, .unknown)
        XCTAssertEqual(screen.defaultVariable(forKey: "future")?.value.stringValue, "34")
    }

    // MARK: - nulls the backend can emit

    func testAScreenWithoutABodySkipsItselfOutOfTheList() throws {
        // Go pointers without omitempty: a screen the builder never published
        // arrives with `body: null`. It cannot be rendered — but the screens
        // next to it can, and nulling the whole list loses them too.
        let json = """
        [{"id": "broken", "body": null, "context_key": "a"},
         {"id": "good", "body": "<html>hi</html>", "context_key": "b"}]
        """
        let decoder = JSONDecoder()

        let list: NoCodesScreenList = try decoder.decode(NoCodesScreenList.self, from: Data(json.utf8))

        XCTAssertEqual(list.screens.map { $0.id }, ["good"])
    }

    func testANullEntryInTheListIsSkipped() throws {
        // One gateway path yields a bare null element.
        let json = """
        [null, {"id": "good", "body": "<html>hi</html>", "context_key": "b"}]
        """
        let decoder = JSONDecoder()

        let list: NoCodesScreenList = try decoder.decode(NoCodesScreenList.self, from: Data(json.utf8))

        XCTAssertEqual(list.screens.map { $0.id }, ["good"])
    }

    func testAListOfOnlyBrokenScreensDecodesEmptyInsteadOfThrowing() throws {
        let json = """
        [null, {"id": "broken", "body": null, "context_key": "a"}]
        """
        let decoder = JSONDecoder()

        let list: NoCodesScreenList = try decoder.decode(NoCodesScreenList.self, from: Data(json.utf8))

        XCTAssertTrue(list.screens.isEmpty)
    }

    func testANullContextKeyDecodesAsAbsent() throws {
        let json = """
        {"id": "screen-5", "body": "<html></html>", "context_key": null}
        """
        let decoder = JSONDecoder()

        let screen: NoCodesScreen = try decoder.decode(NoCodesScreen.self, from: Data(json.utf8))

        XCTAssertEqual(screen.id, "screen-5")
        XCTAssertNil(screen.contextKey)
    }

    func testAMissingContextKeyDecodesAsAbsent() throws {
        let json = """
        {"id": "screen-6", "body": "<html></html>"}
        """
        let decoder = JSONDecoder()

        let screen: NoCodesScreen = try decoder.decode(NoCodesScreen.self, from: Data(json.utf8))

        XCTAssertNil(screen.contextKey)
    }

    func testASingleScreenWithoutABodyStillFailsToDecode() throws {
        // A screen without HTML is nothing to show: the single-screen fetch has
        // to surface that, not hand back a blank screen.
        let json = """
        {"id": "screen-7", "body": null, "context_key": "a"}
        """
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(NoCodesScreen.self, from: Data(json.utf8)))
    }

    func testDecodesFallbackFileContract() throws {
        let json = """
        {"screens": {"main": {"id": "screen-4", "body": "<html></html>", "context_key": "main", "variables": []}}}
        """
        let data: Data = Data(json.utf8)
        let decoder = JSONDecoder()

        let file: FallbackFile = try decoder.decode(FallbackFile.self, from: data)

        XCTAssertEqual(file.screens["main"]?.id, "screen-4")
        XCTAssertEqual(file.screens["main"]?.contextKey, "main")
    }
}
