//
//  NoCodesErrorTests.swift
//  NoCodesTests
//
//  Message mapping and error composition.
//

import XCTest
@testable import NoCodes

final class NoCodesErrorTests: XCTestCase {

    func testEveryErrorTypeMapsToItsMessage() {
        XCTAssertEqual(NoCodesErrorType.internal.message(), "Internal error occurred.")
        XCTAssertEqual(NoCodesErrorType.sdkInitializationError.message(), "SDK is not initialized. Initialize SDK before calling other functions")
        XCTAssertEqual(NoCodesErrorType.screenLoadingFailed.message(), "Failed to load screen.")
        XCTAssertEqual(NoCodesErrorType.productNotFound.message(), "The product not found.")
        XCTAssertEqual(NoCodesErrorType.productsLoadingFailed.message(), "Failed to load products.")
        XCTAssertEqual(NoCodesErrorType.screenNotFound.message(), "No-Code screen not found.")
        XCTAssertEqual(NoCodesErrorType.clientError.message(), "An error occurred in the client code")
    }

    func testUnmappedTypesShareTheUnknownMessage() {
        let unmapped: [NoCodesErrorType] = [.unknown, .invalidRequest, .invalidResponse, .authorizationFailed, .critical, .rateLimitExceeded]

        for type in unmapped {
            XCTAssertEqual(type.message(), "Unknown error occurred.", "\(type)")
        }
    }

    func testErrorWithoutAnExplicitMessageUsesTheTypeMessage() {
        let error = NoCodesError(type: .screenNotFound)

        XCTAssertEqual(error.message, "No-Code screen not found.")
        XCTAssertNil(error.error)
        XCTAssertNil(error.additionalInfo)
    }

    func testExplicitMessageOverridesTheTypeMessage() {
        let error = NoCodesError(type: .screenLoadingFailed, message: "custom reason")

        XCTAssertEqual(error.message, "custom reason")
    }

    func testUnderlyingNoCodesErrorMessageIsAppended() {
        let underlying = NoCodesError(type: .screenNotFound)
        let error = NoCodesError(type: .screenLoadingFailed, message: nil, error: underlying)

        XCTAssertEqual(error.message, "Failed to load screen.\nNo-Code screen not found.")
    }

    func testUnderlyingForeignErrorDescriptionIsAppended() {
        let userInfo: [String: String] = [NSLocalizedDescriptionKey: "connection lost"]
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: userInfo)
        let error = NoCodesError(type: .invalidResponse, message: nil, error: underlying)

        XCTAssertEqual(error.message, "Unknown error occurred.\nconnection lost")
    }

    func testAdditionalInfoIsKept() {
        let info: [String: Any] = ["message": "Not Found"]
        let error = NoCodesError(type: .screenNotFound, message: nil, error: nil, additionalInfo: info)

        XCTAssertEqual(error.additionalInfo?["message"] as? String, "Not Found")
    }

    func testInitializationErrorFactoryCarriesTheInitializationType() {
        let error: NoCodesError = NoCodesError.initializationError()

        XCTAssertEqual(error.type, .sdkInitializationError)
        XCTAssertEqual(error.message, NoCodesErrorType.sdkInitializationError.message())
    }

    func testClientErrorFactoryWrapsTheClientFailure() {
        let userInfo: [String: String] = [NSLocalizedDescriptionKey: "the app said no"]
        let clientError = NSError(domain: "SampleApp", code: 7, userInfo: userInfo)

        let error: NoCodesError = NoCodesError.fromClientError(clientError)

        XCTAssertEqual(error.type, .clientError)
        XCTAssertEqual(error.message, "An error occurred in the client code\nthe app said no")
        XCTAssertNotNil(error.error)
    }

    func testClientErrorFactoryToleratesAMissingUnderlyingError() {
        let error: NoCodesError = NoCodesError.fromClientError(nil)

        XCTAssertEqual(error.type, .clientError)
        XCTAssertEqual(error.message, "An error occurred in the client code")
    }
}
