//
//  PurchaseOptionsTests.swift
//  QonversionUnitTests
//
//  PurchaseOptions travel two ways: store-affecting options (quantity, promo
//  offer) go to StoreKit, association options (contextKeys, screenUid) go to
//  the backend with the purchase report (TDD — written before the implementation).
//

import XCTest
@testable import Qonversion

final class PurchaseOptionsTests: XCTestCase {

    func testDefaults() {
        let options = Qonversion.PurchaseOptions()

        XCTAssertEqual(options.quantity, 1)
        XCTAssertNil(options.contextKeys)
        XCTAssertNil(options.screenUid)
        XCTAssertNil(options.promoOffer)
    }

    func testCustomValuesAreStored() {
        let offer = Qonversion.PromotionalOffer(
            offerId: "promo_1",
            keyId: "key_1",
            nonce: UUID(),
            signature: Data([0x01]),
            timestamp: 1_700_000_000_000
        )
        let options = Qonversion.PurchaseOptions(quantity: 3, contextKeys: ["main"], screenUid: "screen_1", promoOffer: offer)

        XCTAssertEqual(options.quantity, 3)
        XCTAssertEqual(options.contextKeys, ["main"])
        XCTAssertEqual(options.screenUid, "screen_1")
        XCTAssertEqual(options.promoOffer?.offerId, "promo_1")
        XCTAssertEqual(options.promoOffer?.keyId, "key_1")
    }
}
