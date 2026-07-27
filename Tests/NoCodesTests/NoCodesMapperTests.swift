//
//  NoCodesMapperTests.swift
//  NoCodesTests
//

import XCTest
import Qonversion
@testable import NoCodes

final class NoCodesMapperTests: XCTestCase {

    func testMapsProductsWithoutStoreProductToIdentifiersOnly() throws {
        let product: Qonversion.Product = try makeProduct(qonversionId: "premium", storeId: "com.test.premium")
        let mapper = NoCodesMapper()

        let payload: [String: Any] = mapper.map(products: ["premium": product])

        let data = try XCTUnwrap(payload["data"] as? [String: Any])
        let productInfo = try XCTUnwrap(data["premium"] as? [String: Any])
        XCTAssertEqual(productInfo["id"] as? String, "premium")
        XCTAssertEqual(productInfo["store_id"] as? String, "com.test.premium")
        // Without a linked store product nothing else is known, and the web
        // builder must not receive placeholder pricing.
        XCTAssertEqual(productInfo.count, 2)
        // The payload has to survive the JSONSerialization step the screen uses.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload))
    }

    func testMapsRawActionToKnownAndUnknownTypes() {
        let mapper = NoCodesMapper()
        let rawPurchase: [String: Any] = ["data": ["type": "makePurchase", "parameters": ["productId": "premium"]]]
        let rawFuture: [String: Any] = ["data": ["type": "somethingNew"]]

        let purchase: NoCodesAction = mapper.map(rawAction: rawPurchase)
        let future: NoCodesAction = mapper.map(rawAction: rawFuture)

        XCTAssertEqual(purchase.type, .purchase)
        XCTAssertEqual(purchase.parameters?["productId"] as? String, "premium")
        XCTAssertEqual(future.type, .unknown)
    }

    func testMapsWireValuesOfPeriodsAndOffers() {
        let mapper = NoCodesMapper()

        XCTAssertEqual(mapper.map(periodUnit: .day), "day")
        XCTAssertEqual(mapper.map(periodUnit: .week), "week")
        XCTAssertEqual(mapper.map(periodUnit: .month), "month")
        XCTAssertEqual(mapper.map(periodUnit: .year), "year")
        XCTAssertEqual(mapper.map(periodUnit: .unknown), "")

        XCTAssertEqual(mapper.map(introPriceType: .introductory), "intro")
        XCTAssertEqual(mapper.map(introPriceType: .promotional), "promo")
        XCTAssertEqual(mapper.map(introPriceType: .unknown), "")
        // The builder knows "intro" and "promo" only, and a win-back offer is
        // never the introductory offer this value describes.
        XCTAssertEqual(mapper.map(introPriceType: .winBack), "")

        XCTAssertEqual(mapper.map(introPricePaymentType: .freeTrial), "trial")
        XCTAssertEqual(mapper.map(introPricePaymentType: .payUpFront), "pay_up_front")
        XCTAssertEqual(mapper.map(introPricePaymentType: .payAsYouGo), "pay_as_you_go")
        XCTAssertEqual(mapper.map(introPricePaymentType: .unknown), "")
    }

    // MARK: - Private

    /// StoreKit products cannot be constructed in a unit test, so the product
    /// comes from the wire payload and stays un-enriched.
    private func makeProduct(qonversionId: String, storeId: String) throws -> Qonversion.Product {
        let json = """
        {"id": "\(qonversionId)", "apple_product_id": "\(storeId)"}
        """
        let data: Data = Data(json.utf8)
        let decoder = JSONDecoder()

        return try decoder.decode(Qonversion.Product.self, from: data)
    }
}
