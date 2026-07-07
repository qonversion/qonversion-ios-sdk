//
//  EntitlementsServiceTests.swift
//  QonversionUnitTests
//

import XCTest
@testable import Qonversion

final class EntitlementsServiceTests: XCTestCase {

    func testEntitlementsSendsGetRequestAndDecodesWrapper() async throws {
        let processor = MockRequestProcessor()
        let json = #"{"data": [{"id": "premium", "active": true, "started": 1700000000, "expires": 1702600000, "source": "appstore", "product": {"product_id": "pro"}}, {"id": "lifetime", "active": true, "started": 1700000000, "expires": 0, "source": "weird_new_source"}]}"#
        let list = try JSONDecoder().decode(Qonversion.EntitlementsList.self, from: Data(json.utf8))
        processor.results = [list]
        let service = EntitlementsService(requestProcessor: processor)

        let entitlements = try await service.entitlements(userId: "QON_x")

        XCTAssertEqual(processor.processedRequests, [Request.entitlements(userId: "QON_x")])
        XCTAssertEqual(entitlements.count, 2)

        let premium = entitlements.first { $0.id == "premium" }
        XCTAssertEqual(premium?.active, true)
        XCTAssertEqual(premium?.source, .appStore)
        XCTAssertEqual(premium?.productId, "pro")
        XCTAssertEqual(premium?.expirationDate, Date(timeIntervalSince1970: 1_702_600_000))

        let lifetime = entitlements.first { $0.id == "lifetime" }
        XCTAssertNil(lifetime?.expirationDate, "expires == 0 means a lifetime grant")
        XCTAssertEqual(lifetime?.source, .unknown, "unknown source strings must not fail decoding")
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
