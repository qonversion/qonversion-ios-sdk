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

    func testUnderlyingErrorIsPreservedAndAppendedToTheMessage() {
        let underlying = URLError(.notConnectedToInternet)
        let error = QonversionError(type: .productsLoadingFailed, message: nil, error: underlying)

        XCTAssertEqual(error.error as? URLError, underlying)
        XCTAssertTrue(error.message.hasPrefix(QonversionErrorType.productsLoadingFailed.message()))
    }
}
