//
//  QonversionErrorTests.swift
//  QonversionUnitTests
//
//  The error surface is public: host apps distinguish a user cancellation
//  from a pending purchase from a network failure by the error type.
//

import XCTest
@testable import Qonversion

final class QonversionErrorTests: XCTestCase {

    func testThrownErrorIsCatchableWithATypedSwitch() {
        let error: Error = QonversionError(type: .purchaseCancelled)

        guard let qonversionError = error as? QonversionError else {
            return XCTFail("Expected QonversionError")
        }
        switch qonversionError.type {
        case .purchaseCancelled:
            break
        default:
            XCTFail("Expected .purchaseCancelled, got \(qonversionError.type)")
        }
    }

    func testLocalizedDescriptionExposesTheMessage() {
        let error = QonversionError(type: .purchasePending)

        XCTAssertEqual(error.localizedDescription, QonversionErrorType.purchasePending.message())
        XCTAssertEqual((error as Error).localizedDescription, QonversionErrorType.purchasePending.message())
    }

    func testBackendErrorCodeAndTypeReachThePublicError() {
        let handler = NetworkErrorHandler(
            criticalErrorCodes: [.unauthorized, .paymentRequired, .forbidden],
            decoder: ResponseDecoder(decoder: JSONDecoder())
        )
        let body = Data(#"{"error": {"code": "receipt_validation_error", "message": "bad receipt", "type": "invalid_request"}}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api2.qonversion.io/v4/users/u/purchases")!, statusCode: 400, httpVersion: nil, headerFields: nil)!

        let error = handler.extractError(from: response, body: body)

        XCTAssertEqual(error?.apiCode, "receipt_validation_error")
        XCTAssertEqual(error?.apiType, "invalid_request")
    }

    func testUnderlyingErrorIsPreservedAndAppendedToTheMessage() {
        let underlying = URLError(.notConnectedToInternet)
        let error = QonversionError(type: .productsLoadingFailed, message: nil, error: underlying)

        XCTAssertEqual(error.error as? URLError, underlying)
        XCTAssertTrue(error.message.hasPrefix(QonversionErrorType.productsLoadingFailed.message()))
    }
}
