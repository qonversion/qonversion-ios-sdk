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

    func testMissingEnvelopeFallsBackToTheStatusReasonPhrase() {
        // "Unknown error occurred." tells the integrator nothing; the status
        // reason phrase at least names what the server answered.
        let internalError = handler.extractError(from: httpResponse(statusCode: 500), body: Data("not json".utf8))
        XCTAssertEqual(internalError?.message, HTTPURLResponse.localizedString(forStatusCode: 500))

        let unknownError = handler.extractError(from: httpResponse(statusCode: 404), body: Data())
        XCTAssertEqual(unknownError?.message, HTTPURLResponse.localizedString(forStatusCode: 404))
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

    // MARK: - status code propagation

    func testErrorCarriesHttpStatusCodeInAdditionalInfo() {
        let handler = NetworkErrorHandler(criticalErrorCodes: [.unauthorized, .paymentRequired, .forbidden], decoder: ResponseDecoder(decoder: JSONDecoder()))
        let response = HTTPURLResponse(url: URL(string: "https://api.qonversion.io/v3/identities/x")!, statusCode: 404, httpVersion: nil, headerFields: nil)!

        let error = handler.extractError(from: response, body: Data())

        XCTAssertEqual(error?.additionalInfo?["statusCode"] as? Int, 404)
    }
}

// MARK: - API error body handling

final class ApiErrorMappingTests: XCTestCase {

    private var handler: NetworkErrorHandler!

    override func setUp() {
        super.setUp()
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .qonversionTolerant
        handler = NetworkErrorHandler(
            criticalErrorCodes: [.unauthorized, .paymentRequired, .forbidden],
            decoder: ResponseDecoder(decoder: jsonDecoder)
        )
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    private func response(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.qonversion.io/v4/users/u")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    func testPartialErrorBodyStillYieldsTheApiCode() throws {
        // A body carrying the code but neither type nor anything else must
        // not fall back to "no API error at all".
        let body = Data(#"{"error": {"code": "20102", "message": "Receipt validation failed"}}"#.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

        XCTAssertEqual(error.apiCode, "20102")
        XCTAssertNil(error.apiType)
        XCTAssertTrue(error.message.contains("Receipt validation failed"))
    }

    func testMessagelessBodyUsesTheStatusReasonPhrase() throws {
        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 404), body: Data("{}".utf8)))

        XCTAssertEqual(error.message, HTTPURLResponse.localizedString(forStatusCode: 404))
        XCTAssertNotEqual(error.errorDescription, QonversionErrorType.unknown.message(), "the integrator must get more than \"Unknown error occurred.\"")
    }

    func testTheLiveV4SlugVocabularyMapsToTypedErrors() throws {
        // The slugs below are the ones the v4 gateway actually emits to a
        // mobile client (api-gateway / userman / purchaseman / receipter).
        let expectations: [(code: String, type: QonversionErrorType)] = [
            // request family
            ("invalid_data", .invalidRequest),
            ("invalid_request", .invalidRequest),
            ("validation_error", .invalidRequest),
            ("invalid_entitlement_data", .invalidRequest),
            // resource family
            ("not_found", .resourceNotFound),
            ("relation_not_found", .resourceNotFound),
            ("user_not_found", .resourceNotFound),
            // throttling
            ("too_many_requests", .rateLimitExceeded),
            ("rate_limit_exceeded", .rateLimitExceeded),
            // purchase passthrough
            ("purchase_fraud", .fraudPurchase),
            ("store_not_configured", .projectConfigError),
            ("store_creds_failed", .projectConfigError),
            ("subscription_period_parse_error", .receiptValidationError),
            ("apple_purchase_type_error", .receiptValidationError),
            ("conflicting_purchase_found", .receiptValidationError),
            // offer-signature passthrough
            ("token_not_found", .projectConfigError),
            ("secrets_not_found", .projectConfigError),
            ("settings_not_found", .projectConfigError),
        ]

        for expectation in expectations {
            let body = Data("{\"error\": {\"code\": \"\(expectation.code)\", \"message\": \"m\"}}".utf8)
            let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

            XCTAssertEqual(error.type, expectation.type, "code \(expectation.code)")
        }
    }

    func testSlugsWithoutAMeaningOfTheirOwnKeepTheStatusDerivedType() throws {
        // These do reach the client, but they say nothing the HTTP status does
        // not already say — inventing a typed meaning for them would mislead.
        for code in ["already_exists", "storage_error", "network_error", "unknown_error", "unexpected_error", "entity_persistence_error", "client_canceled_request"] {
            let body = Data("{\"error\": {\"code\": \"\(code)\", \"message\": \"m\"}}".utf8)
            let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

            XCTAssertEqual(error.type, .unknown, "code \(code)")
            XCTAssertEqual(error.apiCode, code, "the raw slug still reaches the integrator")
        }
    }

    func testTheSlugsThatNeverExistedAreNotMapped() throws {
        // These were guessed, not observed: no backend ever emits them.
        for code in ["receipt_validation_error", "fraud_purchase", "feature_not_supported", "project_config_error", "invalid_client_uid", "product_not_found", "payment_not_allowed", "store_product_not_available", "rate_limited", "not_implemented"] {
            let body = Data("{\"error\": {\"code\": \"\(code)\", \"message\": \"m\"}}".utf8)
            let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

            XCTAssertEqual(error.type, .unknown, "code \(code)")
        }
    }

    func testAuthorizationSlugsKeepTheirCriticalClassification() throws {
        // control_unauthorized / control_forbidden arrive on 401 / 403, which
        // already latch the revoked-key stop.
        let unauthorized = Data(#"{"error": {"code": "control_unauthorized", "message": "m", "type": "logical"}}"#.utf8)
        let forbidden = Data(#"{"error": {"code": "control_forbidden", "message": "m", "type": "logical"}}"#.utf8)

        XCTAssertEqual(try XCTUnwrap(handler.extractError(from: response(statusCode: 401), body: unauthorized)).type, .critical)
        XCTAssertEqual(try XCTUnwrap(handler.extractError(from: response(statusCode: 403), body: forbidden)).type, .critical)
    }

    func testANumericJsonCodeIsStillACode() throws {
        // Some deployments send the code as a bare number rather than a string.
        let body = Data(#"{"error": {"code": 10008, "message": "m"}}"#.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

        XCTAssertEqual(error.apiCode, "10008")
        XCTAssertEqual(error.type, .fraudPurchase)
    }

    func testTheLegacyNumericTableIsDownToTheOneCodeStillEmitted() throws {
        // v0/v1 numerics are legacy-only. 10008 is the single one a current
        // deployment can still answer with; the rest were dead rows.
        for code in ["10004", "10005", "20005", "20012", "20014", "20102", "21099"] {
            let body = Data("{\"error\": {\"code\": \"\(code)\", \"message\": \"m\", \"type\": \"t\"}}".utf8)
            let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

            XCTAssertEqual(error.type, .unknown, "code \(code)")
        }
    }

    func testTheV4DetailsArrayIsTolerated() throws {
        // The v4 envelope is {"error": {type, code, message, details:[{field, message}]}}.
        let body = Data("""
        {"error": {"type": "request", "code": "invalid_data", "message": "Validation failed", "details": [{"field": "purchase.product_id", "message": "is required"}]}}
        """.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 422), body: body))

        XCTAssertEqual(error.type, .invalidRequest)
        XCTAssertEqual(error.apiCode, "invalid_data")
        XCTAssertEqual(error.apiType, "request")
        XCTAssertTrue(error.message.contains("Validation failed"))
    }

    func testTheWebEnvelopeWithoutATypeIsTolerated() throws {
        // The /v4/web surface answers without the "type" member.
        let body = Data(#"{"error": {"code": "too_many_requests", "message": "Slow down"}}"#.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 429), body: body))

        XCTAssertEqual(error.type, .rateLimitExceeded)
        XCTAssertNil(error.apiType)
        XCTAssertTrue(error.message.contains("Slow down"))
    }

    func testAMessagelessEnvelopeStillYieldsTheCode() throws {
        // The code drives the typed mapping: a body that carries only the code
        // and the details must not lose it to a failed decode.
        let body = Data(#"{"error": {"code": "relation_not_found", "details": [{"field": "uid", "message": "unknown"}]}}"#.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 404), body: body))

        XCTAssertEqual(error.type, .resourceNotFound)
        XCTAssertEqual(error.apiCode, "relation_not_found")
        XCTAssertEqual(error.message, HTTPURLResponse.localizedString(forStatusCode: 404))
    }

    func testAnUnknownSlugKeepsTheStatusDerivedType() throws {
        let body = Data(#"{"error": {"code": "brand_new_backend_slug", "message": "m"}}"#.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

        XCTAssertEqual(error.type, .unknown)
        XCTAssertEqual(error.apiCode, "brand_new_backend_slug")
    }

    func testAnUnmappedCodeKeepsTheStatusDerivedType() throws {
        let body = Data(#"{"error": {"code": "99999", "message": "m", "type": "t"}}"#.utf8)

        let error = try XCTUnwrap(handler.extractError(from: response(statusCode: 400), body: body))

        XCTAssertEqual(error.type, .unknown)
    }

    func testCriticalAndServerClassificationsSurviveTheCodeRefinement() throws {
        // 401/402/403 latch the revoked-key stop and 5xx drives the offline
        // fallback: a backend code must not take those meanings away.
        let body = Data(#"{"error": {"code": "purchase_fraud", "message": "m", "type": "logical"}}"#.utf8)

        let critical = try XCTUnwrap(handler.extractError(from: response(statusCode: 401), body: body))
        let server = try XCTUnwrap(handler.extractError(from: response(statusCode: 503), body: body))

        XCTAssertEqual(critical.type, .critical)
        XCTAssertEqual(server.type, .internal)
    }
}
