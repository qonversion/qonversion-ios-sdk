//
//  TransactionMappingTests.swift
//  QonversionUnitTests
//
//  Pins the StoreKit -> Qonversion mappings on Qonversion.Transaction: environment,
//  ownership type and reason. The StoreKit sources are RawRepresentable structs whose
//  raw spellings ("Production", "FAMILY_SHARED", "RENEWAL") do not match the Swift case
//  names, so the mappings are driven by the StoreKit values themselves, never by rawValue.
//

import XCTest
import StoreKit
@testable import Qonversion

final class TransactionMappingTests: XCTestCase {

    // MARK: - Environment

    func testEnvironmentMapsProduction() throws {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) else {
            throw XCTSkip("AppStore.Environment requires macOS 13")
        }

        let mapped: Qonversion.Transaction.Environment? = Qonversion.Transaction.Environment.from(environment: StoreKit.AppStore.Environment.production)

        XCTAssertEqual(mapped, Qonversion.Transaction.Environment.production)
    }

    func testEnvironmentMapsSandbox() throws {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) else {
            throw XCTSkip("AppStore.Environment requires macOS 13")
        }

        let mapped: Qonversion.Transaction.Environment? = Qonversion.Transaction.Environment.from(environment: StoreKit.AppStore.Environment.sandbox)

        XCTAssertEqual(mapped, Qonversion.Transaction.Environment.sandbox)
    }

    func testEnvironmentMapsXcode() throws {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) else {
            throw XCTSkip("AppStore.Environment requires macOS 13")
        }

        let mapped: Qonversion.Transaction.Environment? = Qonversion.Transaction.Environment.from(environment: StoreKit.AppStore.Environment.xcode)

        XCTAssertEqual(mapped, Qonversion.Transaction.Environment.xcode)
    }

    func testEnvironmentMapsUnknownValueToNil() throws {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) else {
            throw XCTSkip("AppStore.Environment requires macOS 13")
        }
        let unknown = StoreKit.AppStore.Environment(rawValue: "FutureEnvironment")

        let mapped: Qonversion.Transaction.Environment? = Qonversion.Transaction.Environment.from(environment: unknown)

        XCTAssertNil(mapped)
    }

    func testEnvironmentMapsNilToNil() throws {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *) else {
            throw XCTSkip("AppStore.Environment requires macOS 13")
        }

        let mapped: Qonversion.Transaction.Environment? = Qonversion.Transaction.Environment.from(environment: nil)

        XCTAssertNil(mapped)
    }

    // MARK: - OwnershipType

    func testOwnershipTypeMapsPurchased() {
        let mapped: Qonversion.Transaction.OwnershipType = Qonversion.Transaction.OwnershipType.from(ownershipType: StoreKit.Transaction.OwnershipType.purchased)

        XCTAssertEqual(mapped, Qonversion.Transaction.OwnershipType.purchased)
    }

    func testOwnershipTypeMapsFamilyShared() {
        let mapped: Qonversion.Transaction.OwnershipType = Qonversion.Transaction.OwnershipType.from(ownershipType: StoreKit.Transaction.OwnershipType.familyShared)

        XCTAssertEqual(mapped, Qonversion.Transaction.OwnershipType.familyShared)
    }

    func testOwnershipTypeMapsUnknownValueToPurchased() {
        let unknown = StoreKit.Transaction.OwnershipType(rawValue: "FUTURE_TYPE")

        let mapped: Qonversion.Transaction.OwnershipType = Qonversion.Transaction.OwnershipType.from(ownershipType: unknown)

        XCTAssertEqual(mapped, Qonversion.Transaction.OwnershipType.purchased)
    }

    func testOwnershipTypeMapsNilToPurchased() {
        let mapped: Qonversion.Transaction.OwnershipType = Qonversion.Transaction.OwnershipType.from(ownershipType: nil)

        XCTAssertEqual(mapped, Qonversion.Transaction.OwnershipType.purchased)
    }

    // MARK: - Reason

    func testReasonMapsPurchase() throws {
        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) else {
            throw XCTSkip("Transaction.Reason requires macOS 14")
        }

        let mapped: Qonversion.Transaction.Reason = Qonversion.Transaction.Reason.from(reason: StoreKit.Transaction.Reason.purchase)

        XCTAssertEqual(mapped, Qonversion.Transaction.Reason.purchase)
    }

    func testReasonMapsRenewal() throws {
        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) else {
            throw XCTSkip("Transaction.Reason requires macOS 14")
        }

        let mapped: Qonversion.Transaction.Reason = Qonversion.Transaction.Reason.from(reason: StoreKit.Transaction.Reason.renewal)

        XCTAssertEqual(mapped, Qonversion.Transaction.Reason.renewal)
    }

    func testReasonMapsUnknownValueToPurchase() throws {
        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) else {
            throw XCTSkip("Transaction.Reason requires macOS 14")
        }
        let unknown = StoreKit.Transaction.Reason(rawValue: "FUTURE_REASON")

        let mapped: Qonversion.Transaction.Reason = Qonversion.Transaction.Reason.from(reason: unknown)

        XCTAssertEqual(mapped, Qonversion.Transaction.Reason.purchase)
    }

    func testReasonMapsNilToPurchase() throws {
        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) else {
            throw XCTSkip("Transaction.Reason requires macOS 14")
        }

        let mapped: Qonversion.Transaction.Reason = Qonversion.Transaction.Reason.from(reason: nil)

        XCTAssertEqual(mapped, Qonversion.Transaction.Reason.purchase)
    }

    // MARK: - StoreKit raw spellings

    func testStoreKitRawSpellingsDifferFromSwiftCaseNames() throws {
        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) else {
            throw XCTSkip("Transaction.Reason requires macOS 14")
        }

        XCTAssertEqual(StoreKit.AppStore.Environment.production.rawValue, "Production")
        XCTAssertEqual(StoreKit.AppStore.Environment.sandbox.rawValue, "Sandbox")
        XCTAssertEqual(StoreKit.AppStore.Environment.xcode.rawValue, "Xcode")
        XCTAssertEqual(StoreKit.Transaction.OwnershipType.purchased.rawValue, "PURCHASED")
        XCTAssertEqual(StoreKit.Transaction.OwnershipType.familyShared.rawValue, "FAMILY_SHARED")
        XCTAssertEqual(StoreKit.Transaction.Reason.purchase.rawValue, "PURCHASE")
        XCTAssertEqual(StoreKit.Transaction.Reason.renewal.rawValue, "RENEWAL")
    }
}
