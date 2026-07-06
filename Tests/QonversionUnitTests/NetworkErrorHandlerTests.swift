//
//  NetworkErrorHandlerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for NetworkErrorHandler built exactly the way MiscAssembly
//  wires it: critical codes [401, 402, 403] and the real ResponseDecoder with
//  a secondsSince1970 JSONDecoder.
//

import XCTest
@testable import Qonversion

final class NetworkErrorHandlerTests: XCTestCase {

    private var handler: NetworkErrorHandler!

    override func setUp() {
        super.setUp()
        // Mirrors MiscAssembly.errorHandler() wiring.
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970
        handler = NetworkErrorHandler(
            criticalErrorCodes: [.unauthorized, .paymentRequired, .forbidden],
            decoder: ResponseDecoder(decoder: jsonDecoder)
        )
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.qonversion.io/v3/users/u")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - Success codes

    func testSuccessCodesProduceNoError() {
        for code in [200, 201, 204, 299] {
            XCTAssertNil(handler.extractError(from: httpResponse(statusCode: code), body: Data()), "Expected nil for \(code)")
        }
    }

    // MARK: - Internal errors (500...599)

    func testInternalServerErrorCodesProduceInternalError() {
        for code in [500, 502, 599] {
            let error = handler.extractError(from: httpResponse(statusCode: code), body: Data())
            XCTAssertEqual(error?.type, .internal, "Expected .internal for \(code)")
        }
    }

    // MARK: - Critical errors (401, 402, 403)

    func testCriticalCodesProduceCriticalError() {
        for code in [401, 402, 403] {
            let error = handler.extractError(from: httpResponse(statusCode: code), body: Data())
            XCTAssertEqual(error?.type, .critical, "Expected .critical for \(code)")
        }
    }

    // MARK: - Other non-2xx codes

    func testOtherClientErrorCodesProduceUnknownError() {
        for code in [400, 404, 422, 429] {
            let error = handler.extractError(from: httpResponse(statusCode: code), body: Data())
            XCTAssertEqual(error?.type, .unknown, "Expected .unknown for \(code)")
        }
    }

    func testInformationalAndRedirectCodesProduceUnknownError() {
        // Fixates current behavior: anything outside 200...299 that is not internal
        // or critical is treated as an error — including 1xx and 3xx responses.
        for code in [100, 301, 304] {
            let error = handler.extractError(from: httpResponse(statusCode: code), body: Data())
            XCTAssertEqual(error?.type, .unknown, "Expected .unknown for \(code)")
        }
    }

    // MARK: - ApiError envelope parsing

    func testApiErrorEnvelopeMessageIsUsed() throws {
        let body = Data("""
        {"error": {"code": "some_code", "message": "Something exploded", "type": "validation"}}
        """.utf8)
        let error = handler.extractError(from: httpResponse(statusCode: 422), body: body)
        XCTAssertEqual(error?.type, .unknown)
        XCTAssertEqual(error?.message, "Something exploded")
    }

    func testMissingEnvelopeFallsBackToTypeMessage() {
        let internalError = handler.extractError(from: httpResponse(statusCode: 500), body: Data("not json".utf8))
        XCTAssertEqual(internalError?.message, "Internal error occurred.")

        let unknownError = handler.extractError(from: httpResponse(statusCode: 404), body: Data())
        XCTAssertEqual(unknownError?.message, "Unknown error occurred.")
    }

    func testAdditionalInfoContainsLocalizedStatusMessage() throws {
        // Fixates current behavior: additionalInfo always carries the HTTP localized
        // status string under the "message" key (flagged in code with #warning as
        // potentially useless).
        let error = handler.extractError(from: httpResponse(statusCode: 404), body: Data())
        let info = try XCTUnwrap(error?.additionalInfo)
        XCTAssertEqual(info["message"] as? String, HTTPURLResponse.localizedString(forStatusCode: 404))
    }

    // MARK: - Non-HTTP response

    func testNonHTTPResponseProducesNoError() {
        // Fixates current behavior: a non-HTTPURLResponse is silently treated as success.
        let response = URLResponse(
            url: URL(string: "https://api.qonversion.io")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
        XCTAssertNil(handler.extractError(from: response, body: Data()))
    }

    // MARK: - QonversionError message composition (used by the handler's output type)

    func testQonversionErrorAppendsUnderlyingErrorDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let error = QonversionError(type: .internal, error: underlying)
        XCTAssertEqual(error.message, "Internal error occurred.\nboom")
    }

    func testQonversionErrorAppendsNestedQonversionErrorMessage() {
        let nested = QonversionError(type: .internal)
        let error = QonversionError(type: .unknown, error: nested)
        XCTAssertEqual(error.message, "Unknown error occurred.\nInternal error occurred.")
    }
}
