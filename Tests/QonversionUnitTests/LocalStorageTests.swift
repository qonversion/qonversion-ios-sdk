//
//  LocalStorageTests.swift
//  QonversionUnitTests
//
//  Fixation tests for the real LocalStorage over an isolated UserDefaults suite.
//

import XCTest
@testable import Qonversion

final class LocalStorageTests: XCTestCase {

    private var storage: LocalStorage!

    override func setUp() {
        super.setUp()
        storage = LocalStorage(userDefaults: TestDefaults.makeIsolated())
    }

    override func tearDown() {
        storage = nil
        super.tearDown()
    }

    // MARK: - object

    func testObjectRoundtrip() {
        storage.set("plain value", forKey: "object.key")

        XCTAssertEqual(storage.object(forKey: "object.key") as? String, "plain value")
    }

    func testObjectReturnsNilForMissingKey() {
        XCTAssertNil(storage.object(forKey: "missing.key"))
    }

    func testSetNilRemovesValue() {
        storage.set("value", forKey: "nil.key")
        storage.set(nil, forKey: "nil.key")

        XCTAssertNil(storage.object(forKey: "nil.key"))
    }

    // MARK: - removeObject

    func testRemoveObjectDeletesStoredValue() {
        storage.set("to be removed", forKey: "remove.key")

        storage.removeObject(forKey: "remove.key")

        XCTAssertNil(storage.object(forKey: "remove.key"))
        XCTAssertNil(storage.string(forKey: "remove.key"))
    }

    // MARK: - string

    func testStringRoundtrip() {
        storage.set("string value", forKey: "string.key")

        XCTAssertEqual(storage.string(forKey: "string.key"), "string value")
    }

    func testStringReturnsNilForMissingKey() {
        XCTAssertNil(storage.string(forKey: "missing.key"))
    }

    // MARK: - integer

    func testIntegerRoundtrip() {
        storage.set(integer: 42, forKey: "int.key")

        XCTAssertEqual(storage.integer(forKey: "int.key"), 42)
    }

    func testIntegerReturnsZeroForMissingKey() {
        XCTAssertEqual(storage.integer(forKey: "missing.key"), 0)
    }

    // MARK: - float

    func testFloatRoundtrip() {
        storage.set(float: 1.5, forKey: "float.key")

        XCTAssertEqual(storage.float(forKey: "float.key"), 1.5)
    }

    func testFloatReturnsZeroForMissingKey() {
        XCTAssertEqual(storage.float(forKey: "missing.key"), 0)
    }

    // MARK: - double

    func testDoubleRoundtrip() {
        storage.set(double: 2.25, forKey: "double.key")

        XCTAssertEqual(storage.double(forKey: "double.key"), 2.25)
    }

    func testDoubleReturnsZeroForMissingKey() {
        XCTAssertEqual(storage.double(forKey: "missing.key"), 0)
    }

    // MARK: - bool

    func testBoolRoundtrip() {
        storage.set(bool: true, forKey: "bool.key")

        XCTAssertTrue(storage.bool(forKey: "bool.key"))
    }

    func testBoolReturnsFalseForMissingKey() {
        XCTAssertFalse(storage.bool(forKey: "missing.key"))
    }

    // MARK: - url

    func testUrlReturnsNilForMissingKey() {
        XCTAssertNil(storage.url(forKey: "missing.key"))
    }

    func testUrlReadsStoredStringAsFileUrl() {
        // Fixates current behavior: the interface has no URL setter, so a URL can
        // only be read back from a stored string, which UserDefaults interprets
        // as a file path.
        storage.set("/tmp/qonversion-test", forKey: "url.key")

        let url = storage.url(forKey: "url.key")

        XCTAssertNotNil(url)
        XCTAssertTrue(url?.isFileURL == true)
        XCTAssertEqual(url?.path, "/tmp/qonversion-test")
    }

    // MARK: - data

    func testDataRoundtrip() {
        let data = Data([0x01, 0x02, 0x03])
        storage.set(data, forKey: "data.key")

        XCTAssertEqual(storage.data(forKey: "data.key"), data)
    }

    func testDataReturnsNilForMissingKey() {
        XCTAssertNil(storage.data(forKey: "missing.key"))
    }

    // MARK: - array

    func testArrayRoundtrip() {
        storage.set(["a", "b", "c"], forKey: "array.key")

        XCTAssertEqual(storage.array(forKey: "array.key") as? [String], ["a", "b", "c"])
    }

    func testArrayReturnsNilForMissingKey() {
        XCTAssertNil(storage.array(forKey: "missing.key"))
    }

    // MARK: - dictionary

    func testDictionaryRoundtrip() {
        storage.set(["name": "qonversion", "count": 2], forKey: "dict.key")

        let dictionary = storage.dictionary(forKey: "dict.key")

        XCTAssertEqual(dictionary?["name"] as? String, "qonversion")
        XCTAssertEqual(dictionary?["count"] as? Int, 2)
    }

    func testDictionaryReturnsNilForMissingKey() {
        XCTAssertNil(storage.dictionary(forKey: "missing.key"))
    }

    // MARK: - type mismatch behavior

    func testTypedGettersReturnDefaultsForMismatchedTypes() {
        storage.set("not a number", forKey: "mismatch.key")

        // UserDefaults conversion behavior: non-numeric string yields defaults.
        XCTAssertEqual(storage.integer(forKey: "mismatch.key"), 0)
        XCTAssertEqual(storage.double(forKey: "mismatch.key"), 0)
        XCTAssertFalse(storage.bool(forKey: "mismatch.key"))
        XCTAssertNil(storage.data(forKey: "mismatch.key"))
        XCTAssertNil(storage.array(forKey: "mismatch.key"))
        XCTAssertNil(storage.dictionary(forKey: "mismatch.key"))
    }
}
