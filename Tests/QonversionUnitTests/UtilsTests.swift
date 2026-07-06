//
//  UtilsTests.swift
//  QonversionUnitTests
//
//  Fixation tests for Sources/Utils: the [String: Any]/[Any] JSON decoding helpers,
//  String.toCurrencySymbol(), Locale.Currency.currencySymbol(), InternalConstants,
//  and Task.delayed from ConcurrencyExtensions.
//

import XCTest
@testable import Qonversion

// Private wrappers to drive the internal free functions
// decode(fromObject:) / decode(fromArray:) through a real JSONDecoder.
private struct UtilsTestsObjectContainer: Decodable {
    let value: [String: Any]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: JSONCodingKeys.self)
        value = decode(fromObject: container)
    }
}

private struct UtilsTestsArrayContainer: Decodable {
    let value: [Any]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        value = decode(fromArray: &container)
    }
}

final class UtilsTests: XCTestCase {

    // MARK: - decode(fromObject:)

    func testDecodeObjectWithPrimitiveValues() throws {
        let data = Data("""
        {"int": 42, "double": 2.5, "string": "hello", "bool": true}
        """.utf8)

        let result = try JSONDecoder().decode(UtilsTestsObjectContainer.self, from: data).value

        XCTAssertEqual(result["int"] as? Int, 42)
        XCTAssertEqual(result["double"] as? Double, 2.5)
        XCTAssertEqual(result["string"] as? String, "hello")
        XCTAssertEqual(result["bool"] as? Bool, true)
        XCTAssertEqual(result.count, 4)
    }

    func testDecodeObjectWholeNumberDoubleBecomesInt() throws {
        // Fixates current behavior: Int is tried before Double, and JSONDecoder accepts
        // an exact whole-number JSON value like 7.0 as Int — so "7.0" comes back as Int 7,
        // losing the floating-point flavor of the original JSON.
        let data = Data("""
        {"value": 7.0}
        """.utf8)

        let result = try JSONDecoder().decode(UtilsTestsObjectContainer.self, from: data).value

        XCTAssertEqual(result["value"] as? Int, 7)
        XCTAssertTrue(result["value"] is Int)
    }

    func testDecodeObjectWithNestedObjectAndArray() throws {
        let data = Data("""
        {"nested": {"a": 1, "b": "x"}, "list": ["y", 2, false]}
        """.utf8)

        let result = try JSONDecoder().decode(UtilsTestsObjectContainer.self, from: data).value

        let nested = try XCTUnwrap(result["nested"] as? [String: Any])
        XCTAssertEqual(nested["a"] as? Int, 1)
        XCTAssertEqual(nested["b"] as? String, "x")

        let list = try XCTUnwrap(result["list"] as? [Any])
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0] as? String, "y")
        XCTAssertEqual(list[1] as? Int, 2)
        XCTAssertEqual(list[2] as? Bool, false)
    }

    func testDecodeObjectKeepsNullKeys() throws {
        let data = Data("""
        {"present": 1, "missing": null}
        """.utf8)

        let result = try JSONDecoder().decode(UtilsTestsObjectContainer.self, from: data).value

        // Null values are stored as a wrapped nil under their key — the key exists.
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.keys.contains("missing"))
        XCTAssertNil(result["missing"] as? Int)
    }

    // MARK: - decode(fromArray:)

    func testDecodeArrayWithMixedValues() throws {
        let data = Data("""
        [1, "a", true, 2.5, {"k": "v"}, [3], null]
        """.utf8)

        let result = try JSONDecoder().decode(UtilsTestsArrayContainer.self, from: data).value

        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result[0] as? Int, 1)
        XCTAssertEqual(result[1] as? String, "a")
        XCTAssertEqual(result[2] as? Bool, true)
        XCTAssertEqual(result[3] as? Double, 2.5)
        let dict = try XCTUnwrap(result[4] as? [String: Any])
        XCTAssertEqual(dict["k"] as? String, "v")
        let nested = try XCTUnwrap(result[5] as? [Any])
        XCTAssertEqual(nested.first as? Int, 3)
        XCTAssertNil(result[6] as? Int)
    }

    // MARK: - String.toCurrencySymbol()

    func testToCurrencySymbolForKnownCurrencyReturnsSymbol() {
        let symbol = "USD".toCurrencySymbol()
        XCTAssertNotNil(symbol)
        XCTAssertFalse(symbol!.isEmpty)
    }

    func testToCurrencySymbolForUnknownCurrencyReturnsNil() {
        // No available locale uses "ZZZ" as its currency code.
        XCTAssertNil("ZZZ".toCurrencySymbol())
    }

    // MARK: - Locale.Currency.currencySymbol()

    func testLocaleCurrencySymbolMatchesStringHelper() throws {
        guard #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) else {
            throw XCTSkip("Locale.Currency requires macOS 13")
        }
        let symbol = Locale.Currency("USD").currencySymbol()
        XCTAssertNotNil(symbol)
        XCTAssertEqual(symbol, "USD".toCurrencySymbol())
    }

    // MARK: - InternalConstants

    func testInternalConstantsRawValues() {
        XCTAssertEqual(InternalConstants.storagePrefix.rawValue, "io.qonversion.sdk.storage.")
        XCTAssertEqual(InternalConstants.appVersionBundleKey.rawValue, "CFBundleShortVersionString")
    }

    // MARK: - ConcurrencyExtensions: Task.delayed

    func testTaskDelayedRunsOperationAfterDelay() async throws {
        let start = Date()
        let task = Task<Int, Error>.delayed(byTimeInterval: 0.1) { 42 }

        let value = try await task.value

        XCTAssertEqual(value, 42)
        // Small tolerance for nanosecond truncation in the delay conversion.
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.09)
    }
}
