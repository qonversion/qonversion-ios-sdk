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
        let body = Data(#"{"error": {"code": "purchase_fraud", "message": "bad purchase", "type": "logical"}}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api2.qonversion.io/v4/users/u/purchases")!, statusCode: 422, httpVersion: nil, headerFields: nil)!

        let error = handler.extractError(from: response, body: body)

        XCTAssertEqual(error?.apiCode, "purchase_fraud")
        XCTAssertEqual(error?.apiType, "logical")
        XCTAssertEqual(error?.type, .fraudPurchase)
    }

    func testEveryTypeTheBackendMappingProducesCarriesItsOwnMessage() {
        // A type whose message() falls through to "Unknown error occurred."
        // tells the integrator nothing the generic error did not.
        let mapped: [QonversionErrorType] = [.invalidRequest, .resourceNotFound, .rateLimitExceeded, .fraudPurchase, .receiptValidationError, .projectConfigError, .purchaseSceneMissing]

        for type in mapped {
            XCTAssertNotEqual(type.message(), QonversionErrorType.unknown.message(), "\(type) has no message of its own")
        }
    }

    func testTheVisionOSSceneErrorNamesTheCallThatFixesIt() {
        // The only way out of it is an API call, so the message has to name it.
        XCTAssertTrue(QonversionErrorType.purchaseSceneMissing.message().contains("setPurchaseConfirmationScene"))
    }

    func testUnderlyingErrorIsPreservedAndAppendedToTheMessage() {
        let underlying = URLError(.notConnectedToInternet)
        let error = QonversionError(type: .productsLoadingFailed, message: nil, error: underlying)

        XCTAssertEqual(error.error as? URLError, underlying)
        XCTAssertTrue(error.message.hasPrefix(QonversionErrorType.productsLoadingFailed.message()))
    }

    // MARK: - the backend classification survives the service wrapping

    func testWrappingABackendErrorKeepsItsApiCodeAndApiType() {
        // A service names the operation that failed, but the backend's own
        // classification is what the host branches on.
        let backendError = QonversionError(type: .fraudPurchase, message: "fraud", apiCode: "purchase_fraud", apiType: "logical")

        let wrapped = QonversionError(type: .purchaseReportingFailed, message: nil, error: backendError)

        XCTAssertEqual(wrapped.type, .purchaseReportingFailed)
        XCTAssertEqual(wrapped.apiCode, "purchase_fraud")
        XCTAssertEqual(wrapped.apiType, "logical")
    }

    func testAnExplicitApiCodeWinsOverTheUnderlyingOne() {
        let backendError = QonversionError(type: .fraudPurchase, apiCode: "purchase_fraud", apiType: "logical")

        let wrapped = QonversionError(type: .purchaseReportingFailed, error: backendError, apiCode: "explicit", apiType: "request")

        XCTAssertEqual(wrapped.apiCode, "explicit")
        XCTAssertEqual(wrapped.apiType, "request")
    }

    func testWrappingANonApiErrorLeavesTheClassificationEmpty() {
        let wrapped = QonversionError(type: .purchaseReportingFailed, error: URLError(.notConnectedToInternet))

        XCTAssertNil(wrapped.apiCode)
        XCTAssertNil(wrapped.apiType)
    }

    func testTheClassificationSurvivesTwoLevelsOfWrapping() {
        let backendError = QonversionError(type: .fraudPurchase, apiCode: "purchase_fraud", apiType: "logical")
        let firstWrap = QonversionError(type: .purchaseReportingFailed, error: backendError)

        let secondWrap = QonversionError(type: .productsLoadingFailed, error: firstWrap)

        XCTAssertEqual(secondWrap.apiCode, "purchase_fraud")
        XCTAssertEqual(secondWrap.apiType, "logical")
    }
}
