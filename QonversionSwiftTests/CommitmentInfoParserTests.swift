//
//  CommitmentInfoParserTests.swift
//  QonversionSwiftTests
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import XCTest
import Foundation
@testable import QonversionSwift
import Qonversion

final class CommitmentInfoParserTests: XCTestCase {

  // Apple's canonical decoded-transaction payload, taken from the `commitmentInfo` block of
  // app-store-server-library's `signedTransaction.json`. `Transaction.jsonRepresentation`
  // follows this same schema, so these are the exact keys/encodings the SDK sees in production:
  // commitmentPrice is Int64 milliunits (119880 -> 119.88) and commitmentExpiresDate is epoch ms.
  private let applePayload = """
  {
    "transactionId": "23456",
    "productId": "com.example.product",
    "price": 10990,
    "currency": "USD",
    "expiresDate": 1698149000000,
    "billingPlanType": "MONTHLY",
    "commitmentInfo": {
      "billingPeriodNumber": 3,
      "commitmentExpiresDate": 1698150000000,
      "commitmentPrice": 119880,
      "totalBillingPeriods": 12
    }
  }
  """.data(using: .utf8)!

  // Regression guard for DEV-906: the parser must decode Apple's real commitmentInfo keys.
  // The original implementation read `price`/`expirationDate`, which are absent from Apple's
  // schema, so the decode threw and commitmentInfo was silently always nil.
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
  func testParsesAppleCommitmentInfoSchema() throws {
    let info = try XCTUnwrap(PurchasesMapper().parseCommitmentInfo(from: applePayload))

    XCTAssertEqual(info.billingPeriodNumber, 3)
    XCTAssertEqual(info.totalBillingPeriods, 12)
    // 119880 milliunits -> 119.88 in currency units (the whole-commitment total).
    XCTAssertEqual(info.commitmentPrice.doubleValue, 119.88, accuracy: 0.0001)
    // 1698150000000 ms -> 1698150000 s (the whole-commitment expiry).
    XCTAssertEqual(info.commitmentExpirationDate, Date(timeIntervalSince1970: 1698150000))
  }

  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
  func testReturnsNilWhenCommitmentBlockAbsent() {
    let nonCommitment = #"{"transactionId":"1","productId":"p","price":9990}"#.data(using: .utf8)!
    XCTAssertNil(PurchasesMapper().parseCommitmentInfo(from: nonCommitment))
  }

  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
  func testReturnsNilForMalformedJSON() {
    let garbage = "not json".data(using: .utf8)!
    XCTAssertNil(PurchasesMapper().parseCommitmentInfo(from: garbage))
  }
}
