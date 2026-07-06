//
//  LocalStorageTests.swift
//  QonversionUnitTests
//
//  Fixation tests for the real LocalStorage over an isolated UserDefaults suite.
//

import XCTest
@testable import Qonversion

final class LocalStorageTests: XCTestCase {

    private struct Payload: Codable, Equatable {
        let name: String
        let count: Int
    }

    private var defaults: UserDefaults!
    private var storage: LocalStorage!

    override func setUp() {
        super.setUp()
        defaults = TestDefaults.makeIsolated()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        storage = LocalStorage(userDefaults: defaults, encoder: JSONEncoder(), decoder: decoder)
    }

    override func tearDown() {
        storage = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - typed set / object (Codable round-trip)

    func testTypedRoundtrip() throws {
        let payload = Payload(name: "qonversion", count: 2)

        try storage.set(payload, forKey: "typed.key")
        let restored = try storage.object(forKey: "typed.key", dataType: Payload.self)

        XCTAssertEqual(restored, payload)
    }

    func testTypedSetStoresEncodedData() throws {
        // The typed setter persists JSON Data under the key.
        try storage.set(Payload(name: "q", count: 1), forKey: "typed.data.key")

        XCTAssertNotNil(storage.data(forKey: "typed.data.key"))
    }

    func testTypedObjectReturnsNilForMissingKey() throws {
        XCTAssertNil(try storage.object(forKey: "missing.key", dataType: Payload.self))
    }

    func testTypedSetNilRemovesValue() throws {
        try storage.set(Payload(name: "q", count: 1), forKey: "nil.key")
        try storage.set(nil, forKey: "nil.key")

        XCTAssertNil(try storage.object(forKey: "nil.key", dataType: Payload.self))
    }

    func testTypedObjectThrowsDeserializationErrorOnGarbageData() {
        defaults.set(Data([0xFF, 0x00, 0x12]), forKey: "garbage.key")

        XCTAssertThrowsError(try storage.object(forKey: "garbage.key", dataType: Payload.self)) { error in
            XCTAssertEqual((error as? QonversionError)?.type, .storageDeserializationFailed)
        }
    }

    func testTypedObjectThrowsOnTypeMismatch() throws {
        try storage.set(Payload(name: "q", count: 1), forKey: "mismatch.typed.key")

        XCTAssertThrowsError(try storage.object(forKey: "mismatch.typed.key", dataType: [Int].self)) { error in
            XCTAssertEqual((error as? QonversionError)?.type, .storageDeserializationFailed)
        }
    }

    // MARK: - removeObject

    func testRemoveObjectDeletesStoredValue() {
        storage.set(string: "to be removed", forKey: "remove.key")

        storage.removeObject(forKey: "remove.key")

        XCTAssertNil(storage.string(forKey: "remove.key"))
    }

    // MARK: - string

    func testStringRoundtrip() {
        storage.set(string: "string value", forKey: "string.key")

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
        storage.set(string: "/tmp/qonversion-test", forKey: "url.key")

        let url = storage.url(forKey: "url.key")

        XCTAssertNotNil(url)
        XCTAssertTrue(url?.isFileURL == true)
        XCTAssertEqual(url?.path, "/tmp/qonversion-test")
    }

    // MARK: - raw plist getters (seeded directly into UserDefaults)

    func testDataGetterReadsRawValue() {
        let data = Data([0x01, 0x02, 0x03])
        defaults.set(data, forKey: "data.key")

        XCTAssertEqual(storage.data(forKey: "data.key"), data)
    }

    func testDataReturnsNilForMissingKey() {
        XCTAssertNil(storage.data(forKey: "missing.key"))
    }

    func testArrayGetterReadsRawValue() {
        defaults.set(["a", "b", "c"], forKey: "array.key")

        XCTAssertEqual(storage.array(forKey: "array.key") as? [String], ["a", "b", "c"])
    }

    func testArrayReturnsNilForMissingKey() {
        XCTAssertNil(storage.array(forKey: "missing.key"))
    }

    func testDictionaryGetterReadsRawValue() {
        defaults.set(["name": "qonversion", "count": 2], forKey: "dict.key")

        let dictionary = storage.dictionary(forKey: "dict.key")

        XCTAssertEqual(dictionary?["name"] as? String, "qonversion")
        XCTAssertEqual(dictionary?["count"] as? Int, 2)
    }

    func testDictionaryReturnsNilForMissingKey() {
        XCTAssertNil(storage.dictionary(forKey: "missing.key"))
    }

    // MARK: - type mismatch behavior

    func testTypedGettersReturnDefaultsForMismatchedTypes() {
        storage.set(string: "not a number", forKey: "mismatch.key")

        // UserDefaults conversion behavior: non-numeric string yields defaults.
        XCTAssertEqual(storage.integer(forKey: "mismatch.key"), 0)
        XCTAssertEqual(storage.double(forKey: "mismatch.key"), 0)
        XCTAssertFalse(storage.bool(forKey: "mismatch.key"))
        XCTAssertNil(storage.data(forKey: "mismatch.key"))
        XCTAssertNil(storage.array(forKey: "mismatch.key"))
        XCTAssertNil(storage.dictionary(forKey: "mismatch.key"))
    }
}
