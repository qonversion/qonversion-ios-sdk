//
//  NetworkErrorHandlerTests.swift
//  NoCodesTests
//
//  Status code to NoCodesErrorType classification.
//

import XCTest
@testable import NoCodes

final class NetworkErrorHandlerTests: XCTestCase {

    private var handler: NetworkErrorHandler!

    override func setUp() {
        super.setUp()
        let jsonDecoder = JSONDecoder()
        let responseDecoder = ResponseDecoder(decoder: jsonDecoder)
        let criticalCodes: [ResponseCode] = [.unauthorized, .paymentRequired, .forbidden]
        handler = NetworkErrorHandler(criticalErrorCodes: criticalCodes, decoder: responseDecoder)
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    func testSuccessfulStatusCodesProduceNoError() {
        for statusCode in [200, 201, 204, 299] {
            let response: HTTPURLResponse = makeResponse(statusCode: statusCode)
            let body: Data = Data("{}".utf8)

            XCTAssertNil(handler.extractError(from: response, body: body), "status code \(statusCode)")
        }
    }

    func testServerErrorRangeIsInternal() {
        for statusCode in [500, 502, 599] {
            let response: HTTPURLResponse = makeResponse(statusCode: statusCode)
            let body: Data = Data("{}".utf8)

            XCTAssertEqual(handler.extractError(from: response, body: body)?.type, .internal, "status code \(statusCode)")
        }
    }

    func testProjectKeyRejectionsAreCritical() {
        for statusCode in [401, 402, 403] {
            let response: HTTPURLResponse = makeResponse(statusCode: statusCode)
            let body: Data = Data("{}".utf8)

            XCTAssertEqual(handler.extractError(from: response, body: body)?.type, .critical, "status code \(statusCode)")
        }
    }

    func testNotFoundIsScreenNotFound() {
        let response: HTTPURLResponse = makeResponse(statusCode: 404)
        let body: Data = Data("{}".utf8)

        XCTAssertEqual(handler.extractError(from: response, body: body)?.type, .screenNotFound)
    }

    func testEmptyBodied405ProducesAnUnknownNonCriticalError() {
        // gorilla's methodNotAllowedHandler answers a completely empty body
        // and no Content-Type, bypassing the JSON NotFoundHandler envelope.
        let response: HTTPURLResponse = makeResponse(statusCode: 405)
        let body: Data = Data()

        let error: NoCodesError? = handler.extractError(from: response, body: body)

        XCTAssertEqual(error?.type, .unknown, "405 must not be treated as critical")
        XCTAssertEqual(error?.additionalInfo?[ErrorConstants.statusCodeKey.rawValue] as? Int, 405)
    }

    func testOtherUnsuccessfulCodesAreUnknown() {
        for statusCode in [301, 418, 429] {
            let response: HTTPURLResponse = makeResponse(statusCode: statusCode)
            let body: Data = Data("{}".utf8)

            XCTAssertEqual(handler.extractError(from: response, body: body)?.type, .unknown, "status code \(statusCode)")
        }
    }

    func testNonHTTPResponsesAreNotClassified() {
        let url = URL(string: "https://api2.qonversion.io/v3/screens/screen-1")!
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let body: Data = Data("{}".utf8)

        XCTAssertNil(handler.extractError(from: response, body: body))
    }

    func testApiErrorMessageIsPreferredOverTheStatusText() {
        let response: HTTPURLResponse = makeResponse(statusCode: 404)
        let json = #"{"error": {"code": "screen_not_found", "message": "No screen for this context key", "type": "not_found"}}"#
        let body: Data = Data(json.utf8)

        let error: NoCodesError? = handler.extractError(from: response, body: body)

        XCTAssertEqual(error?.message, "No screen for this context key")
    }

    func testUndecodableBodyFallsBackToTheTypeMessageAndKeepsTheStatusText() {
        let response: HTTPURLResponse = makeResponse(statusCode: 404)
        let body: Data = Data("<html>gateway</html>".utf8)

        let error: NoCodesError? = handler.extractError(from: response, body: body)

        XCTAssertEqual(error?.message, NoCodesErrorType.screenNotFound.message())
        let info: [String: Any] = try! XCTUnwrap(error?.additionalInfo)
        XCTAssertNotNil(info[ErrorConstants.messageKey.rawValue] as? String)
    }

    // MARK: - Private

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        let url = URL(string: "https://api2.qonversion.io/v3/screens/screen-1")!

        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}
