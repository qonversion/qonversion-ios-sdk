//
//  NoCodesContextBuilderTests.swift
//  NoCodesTests
//
//  The JSON handed to the screen runtime as `setContext`.
//

import XCTest
@testable import NoCodes

@MainActor
final class NoCodesContextBuilderTests: XCTestCase {

    private static let alreadyLaunchedKey = "io.qonversion.nocodes.alreadyLaunchedBefore"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.alreadyLaunchedKey)
        super.tearDown()
    }

    // MARK: - Golden context

    func testFullContextCarriesTheDeviceUserAndProductsBlocks() throws {
        let builder = NoCodesContextBuilder()
        let productsContext: [String: any Sendable] = [
            "annual": ["hasIntro": "true", "introType": "free_trial"],
            "monthly": ["hasIntro": "false", "introType": ""],
            "hasAnyIntro": "true"
        ]
        let userProperties: [String: String] = ["_q_email": "sample@qonversion.io"]
        let entitlements: [String] = ["premium", "pro"]

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .dark, activeEntitlementIds: entitlements, productsContext: productsContext, userProperties: userProperties))
        let context: [String: Any] = try decodeContext(json)

        let device: [String: Any] = try XCTUnwrap(context["device"] as? [String: Any])
        XCTAssertEqual(device["theme"] as? String, "dark")
        XCTAssertEqual(device["locale"] as? String, Locale.current.identifier)
        XCTAssertNotNil(device["platform"] as? String)
        XCTAssertNotNil(device["osVersion"] as? String)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertEqual(user["hasAnyEntitlement"] as? String, "true")
        XCTAssertEqual(user["entitlements"] as? [String], entitlements)
        XCTAssertEqual(user["properties"] as? [String: String], userProperties)
        XCTAssertNotNil(user["daysSinceInstall"] as? Int)

        let products: [String: Any] = try XCTUnwrap(context["products"] as? [String: Any])
        let annual: [String: String] = try XCTUnwrap(products["annual"] as? [String: String])
        let monthly: [String: String] = try XCTUnwrap(products["monthly"] as? [String: String])
        // The intro flags travel as strings — the condition evaluator compares them as such.
        XCTAssertEqual(annual["hasIntro"], "true")
        XCTAssertEqual(annual["introType"], "free_trial")
        XCTAssertEqual(monthly["hasIntro"], "false")
        XCTAssertEqual(monthly["introType"], "")
        XCTAssertEqual(products["hasAnyIntro"] as? String, "true")
    }

    func testIntroTypesTravelVerbatim() throws {
        let builder = NoCodesContextBuilder()
        let productsContext: [String: any Sendable] = [
            "trial": ["hasIntro": "true", "introType": "free_trial"],
            "upfront": ["hasIntro": "true", "introType": "pay_up_front"],
            "asYouGo": ["hasIntro": "true", "introType": "pay_as_you_go"],
            "hasAnyIntro": "true"
        ]

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: productsContext))
        let context: [String: Any] = try decodeContext(json)

        let products: [String: Any] = try XCTUnwrap(context["products"] as? [String: Any])
        XCTAssertEqual((products["trial"] as? [String: String])?["introType"], "free_trial")
        XCTAssertEqual((products["upfront"] as? [String: String])?["introType"], "pay_up_front")
        XCTAssertEqual((products["asYouGo"] as? [String: String])?["introType"], "pay_as_you_go")
    }

    func testAnEmptyProductsContextLeavesTheProductsBlockOut() throws {
        let builder = NoCodesContextBuilder()

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let context: [String: Any] = try decodeContext(json)

        XCTAssertNil(context["products"])
    }

    func testNoEntitlementsAreReportedAsTheFalseString() throws {
        let builder = NoCodesContextBuilder()

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let context: [String: Any] = try decodeContext(json)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertEqual(user["hasAnyEntitlement"] as? String, "false")
        XCTAssertEqual(user["entitlements"] as? [String], [])
    }

    func testEmptyUserPropertiesAreOmitted() throws {
        let builder = NoCodesContextBuilder()

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:], userProperties: [:]))
        let context: [String: Any] = try decodeContext(json)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertNil(user["properties"])
    }

    func testResolvedThemeIsReportedVerbatim() throws {
        let builder = NoCodesContextBuilder()

        let lightJson: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let darkJson: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .dark, activeEntitlementIds: [], productsContext: [:]))

        let lightDevice: [String: Any] = try XCTUnwrap(try decodeContext(lightJson)["device"] as? [String: Any])
        let darkDevice: [String: Any] = try XCTUnwrap(try decodeContext(darkJson)["device"] as? [String: Any])
        XCTAssertEqual(lightDevice["theme"] as? String, "light")
        XCTAssertEqual(darkDevice["theme"] as? String, "dark")
    }

    func testTheContextIsWrappedInADataEnvelope() throws {
        let builder = NoCodesContextBuilder()

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))

        let data: Data = Data(json.utf8)
        let wrapper: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(wrapper["data"])
    }

    // MARK: - First launch

    func testFirstLaunchIsResolvedOnceAndIsFalseAfterwards() {
        UserDefaults.standard.removeObject(forKey: Self.alreadyLaunchedKey)
        let builder = NoCodesContextBuilder()
        let daysSinceInstall: Int = builder.calculateDaysSinceInstall()

        let first: Bool = builder.resolveIsFirstLaunch()
        let second: Bool = builder.resolveIsFirstLaunch()

        // The very first resolution reports a first launch only for an app
        // installed today; from then on the answer is always false.
        XCTAssertEqual(first, daysSinceInstall == 0)
        XCTAssertFalse(second)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.alreadyLaunchedKey))
    }

    func testTheFirstLaunchFlagIsSharedAcrossBuilderInstances() {
        UserDefaults.standard.removeObject(forKey: Self.alreadyLaunchedKey)
        let first = NoCodesContextBuilder()
        _ = first.resolveIsFirstLaunch()

        let second = NoCodesContextBuilder()

        XCTAssertFalse(second.resolveIsFirstLaunch())
    }

    func testFirstLaunchIsReportedIntoTheContextAsAString() throws {
        UserDefaults.standard.set(true, forKey: Self.alreadyLaunchedKey)
        let builder = NoCodesContextBuilder()

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let context: [String: Any] = try decodeContext(json)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertEqual(user["isFirstLaunch"] as? String, "false")
    }

    // MARK: - Days since install

    func testDaysSinceInstallIsNeverNegative() {
        let builder = NoCodesContextBuilder()

        XCTAssertGreaterThanOrEqual(builder.calculateDaysSinceInstall(), 0)
    }

    func testDaysSinceInstallIsStableAcrossCalls() {
        let builder = NoCodesContextBuilder()

        XCTAssertEqual(builder.calculateDaysSinceInstall(), builder.calculateDaysSinceInstall())
    }

    // MARK: - Private

    private func decodeContext(_ json: String) throws -> [String: Any] {
        let data: Data = Data(json.utf8)
        let wrapper: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        return try XCTUnwrap(wrapper["data"] as? [String: Any])
    }
}
