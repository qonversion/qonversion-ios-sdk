//
//  ResponseDecoderTests.swift
//  QonversionUnitTests
//
//  Tests for the real ResponseDecoder built by the REAL MiscAssembly: pinning
//  a decoder configured differently from production proves nothing about
//  production. The date strategy under test is therefore .qonversionTolerant,
//  which is what the SDK actually ships.
//

import XCTest
@testable import Qonversion

private struct DecoderTestPayload: Decodable, Equatable {
    let id: String
    let count: Int
    let created: Date
}

final class ResponseDecoderTests: XCTestCase {

    private var decoder: ResponseDecoder!

    override func setUp() {
        super.setUp()
        let internalConfig = InternalConfig(userId: "")
        let miscAssembly = MiscAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)
        decoder = miscAssembly.responseDecoder() as? ResponseDecoder
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    func testDecodesPayloadWithSecondsSince1970Date() throws {
        let data = Data("""
        {"id": "abc", "count": 7, "created": 1700000000}
        """.utf8)

        let result = try decoder.decode(DecoderTestPayload.self, from: data)

        XCTAssertEqual(result.id, "abc")
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.created, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testDecodesRfc3339Dates() throws {
        // The shape the v4 API actually sends; a .secondsSince1970 decoder
        // would fail the whole payload on it.
        let data = Data(#"{"id": "abc", "count": 1, "created": "2023-11-14T22:13:20Z"}"#.utf8)

        let result = try decoder.decode(DecoderTestPayload.self, from: data)

        XCTAssertEqual(result.created, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testDecodesRfc3339DatesWithFractionalSeconds() throws {
        let data = Data(#"{"id": "abc", "count": 1, "created": "2023-11-14T22:13:20.500Z"}"#.utf8)

        let result = try decoder.decode(DecoderTestPayload.self, from: data)

        XCTAssertEqual(result.created.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.001)
    }

    func testDecodesFractionalSecondsDate() throws {
        let data = Data("""
        {"id": "abc", "count": 1, "created": 1700000000.5}
        """.utf8)

        let result = try decoder.decode(DecoderTestPayload.self, from: data)

        XCTAssertEqual(result.created.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.001)
    }

    func testMalformedJSONThrowsDecodingError() {
        let data = Data("not a json at all".utf8)

        XCTAssertThrowsError(try decoder.decode(DecoderTestPayload.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError, "Expected DecodingError, got \(error)")
        }
    }

    func testMissingKeyThrowsDecodingError() {
        let data = Data("""
        {"id": "abc"}
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(DecoderTestPayload.self, from: data)) { error in
            guard case DecodingError.keyNotFound = error else {
                return XCTFail("Expected keyNotFound, got \(error)")
            }
        }
    }

    func testEmptyDataThrowsDecodingError() {
        XCTAssertThrowsError(try decoder.decode(DecoderTestPayload.self, from: Data())) { error in
            XCTAssertTrue(error is DecodingError, "Expected DecodingError, got \(error)")
        }
    }

    func testDecodesEmptyApiResponseFromArbitraryJSON() throws {
        // EmptyApiResponse has no coding keys, so any valid JSON object decodes into it.
        let data = Data("{}".utf8)
        XCTAssertNoThrow(try decoder.decode(EmptyApiResponse.self, from: data))
    }
}
