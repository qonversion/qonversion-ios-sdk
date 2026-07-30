//
//  EntitlementsServiceTests.swift
//  QonversionUnitTests
//

import XCTest
@testable import Qonversion

final class EntitlementsServiceTests: XCTestCase {

    /// The REAL processor over a stubbed transport: decoding the payload in
    /// the test and handing the ready objects to a mock proves nothing about
    /// the decoder the SDK actually ships on this path.
    private func makeLiveService(json: String) -> (EntitlementsService, MockNetworkProvider) {
        let networkProvider = MockNetworkProvider()
        networkProvider.responseData = Data(json.utf8)
        networkProvider.response = HTTPURLResponse(
            url: URL(string: "https://api2.qonversion.io/v4/users/QON_x/entitlements")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let internalConfig = InternalConfig(userId: "QON_x")
        let miscAssembly = MiscAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)
        let processor = RequestProcessor(
            baseURL: "https://api2.qonversion.io/",
            networkProvider: networkProvider,
            headersBuilder: MockHeadersBuilder(),
            errorHandler: miscAssembly.errorHandler(),
            decoder: miscAssembly.responseDecoder(),
            retriableRequestKinds: [],
            requestsStorage: MockRequestsStorage(),
            rateLimiter: MockRateLimiter()
        )

        return (EntitlementsService(requestProcessor: processor), networkProvider)
    }

    func testEntitlementsSendsGetRequestAndDecodesWrapper() async throws {
        // v4 wire shape: is_active/started_at/expires_at (RFC3339, absent =
        // lifetime), renew_state inside product.subscription.
        let json = #"{"data": [{"id": "premium", "is_active": true, "started_at": "2023-11-14T22:13:20Z", "expires_at": "2023-12-15T00:26:40Z", "source": "appstore", "product": {"product_id": "pro", "subscription": {"renew_state": "will_renew"}}}, {"id": "lifetime", "is_active": true, "started_at": "2023-11-14T22:13:20Z", "source": "weird_new_source"}]}"#
        let (service, networkProvider) = makeLiveService(json: json)

        let entitlements = try await service.entitlements(userId: "QON_x")

        XCTAssertEqual(networkProvider.sentRequests.first?.url?.absoluteString, "https://api2.qonversion.io/v4/users/QON_x/entitlements")
        XCTAssertEqual(networkProvider.sentRequests.first?.httpMethod, "GET")
        XCTAssertEqual(entitlements.count, 2)

        let premium = entitlements.first { $0.id == "premium" }
        XCTAssertEqual(premium?.active, true)
        XCTAssertEqual(premium?.source, .appStore)
        XCTAssertEqual(premium?.productId, "pro")
        XCTAssertEqual(premium?.renewState, .willRenew)
        XCTAssertEqual(premium?.expirationDate, Date(timeIntervalSince1970: 1_702_600_000))

        let lifetime = entitlements.first { $0.id == "lifetime" }
        XCTAssertNil(lifetime?.expirationDate, "absent expires_at means a lifetime grant")
        XCTAssertEqual(lifetime?.source, .unknown, "unknown source strings must not fail decoding")
        XCTAssertEqual(lifetime?.renewState, .unknown, "no subscription object means non-renewable only on a source the SDK recognizes; an unknown store claims nothing")
    }

    func testEntitlementsDecodesThePaddleSource() async throws {
        // The backend reports this source for entitlements bought through Paddle.
        let json = #"{"data": [{"id": "premium", "is_active": true, "started_at": "2023-11-14T22:13:20Z", "source": "paddle"}]}"#
        let (service, _) = makeLiveService(json: json)

        let entitlements = try await service.entitlements(userId: "QON_x")

        let entitlement = try XCTUnwrap(entitlements.first { $0.id == "premium" })
        XCTAssertEqual(entitlement.source, .paddle, "paddle must not decode as .unknown")
        XCTAssertEqual(entitlement.renewState, .nonRenewable, "a recognized store with no subscription object is non-renewable")
    }

    func testEntitlementsWrapsErrors() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = EntitlementsService(requestProcessor: processor)

        do {
            _ = try await service.entitlements(userId: "QON_x")
            XCTFail("Expected entitlements to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .entitlementsLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
