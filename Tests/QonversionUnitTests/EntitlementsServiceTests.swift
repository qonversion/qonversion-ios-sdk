//
//  EntitlementsServiceTests.swift
//  QonversionUnitTests
//

import XCTest
@testable import Qonversion

final class EntitlementsServiceTests: XCTestCase {

    func testEntitlementsSendsGetRequestAndDecodesWrapper() async throws {
        let processor = MockRequestProcessor()
        // v4 wire shape: is_active/started_at/expires_at (RFC3339, absent =
        // lifetime), renew_state inside product.subscription.
        let json = #"{"data": [{"id": "premium", "is_active": true, "started_at": "2023-11-14T22:13:20Z", "expires_at": "2023-12-15T00:26:40Z", "source": "appstore", "product": {"product_id": "pro", "subscription": {"renew_state": "will_renew"}}}, {"id": "lifetime", "is_active": true, "started_at": "2023-11-14T22:13:20Z", "source": "weird_new_source"}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(Qonversion.EntitlementsList.self, from: Data(json.utf8))
        processor.results = [list]
        let service = EntitlementsService(requestProcessor: processor)

        let entitlements = try await service.entitlements(userId: "QON_x")

        XCTAssertEqual(processor.processedRequests, [Request.entitlements(userId: "QON_x")])
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
        XCTAssertEqual(lifetime?.renewState, .unknown)
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
