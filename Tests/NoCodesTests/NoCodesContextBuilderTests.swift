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

    // MARK: - Golden context

    func testFullContextCarriesTheDeviceUserAndProductsBlocks() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)
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
        let builder = NoCodesContextBuilder(isFirstLaunch: false)
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
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let context: [String: Any] = try decodeContext(json)

        XCTAssertNil(context["products"])
    }

    func testNoEntitlementsAreReportedAsTheFalseString() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let context: [String: Any] = try decodeContext(json)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertEqual(user["hasAnyEntitlement"] as? String, "false")
        XCTAssertEqual(user["entitlements"] as? [String], [])
    }

    func testEmptyUserPropertiesAreOmitted() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:], userProperties: [:]))
        let context: [String: Any] = try decodeContext(json)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertNil(user["properties"])
    }

    func testResolvedThemeIsReportedVerbatim() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        let lightJson: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let darkJson: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .dark, activeEntitlementIds: [], productsContext: [:]))

        let lightDevice: [String: Any] = try XCTUnwrap(try decodeContext(lightJson)["device"] as? [String: Any])
        let darkDevice: [String: Any] = try XCTUnwrap(try decodeContext(darkJson)["device"] as? [String: Any])
        XCTAssertEqual(lightDevice["theme"] as? String, "light")
        XCTAssertEqual(darkDevice["theme"] as? String, "dark")
    }

    func testTheContextIsWrappedInADataEnvelope() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))

        let data: Data = Data(json.utf8)
        let wrapper: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(wrapper["data"])
    }

    // MARK: - First launch

    /// The answer is latched at SDK initialization, not on the first context
    /// build: every screen of the launch has to see the same value, and the
    /// builder itself only carries what was decided there.
    func testTheBuilderReportsTheAnswerItWasBuiltWithOnEveryScreen() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: true)

        XCTAssertTrue(builder.resolveIsFirstLaunch())
        XCTAssertTrue(builder.resolveIsFirstLaunch(), "a second screen of the same launch sees the same answer")

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let user: [String: Any] = try XCTUnwrap(try decodeContext(json)["user"] as? [String: Any])
        XCTAssertEqual(user["isFirstLaunch"] as? String, "true")

        let secondJson: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let secondUser: [String: Any] = try XCTUnwrap(try decodeContext(secondJson)["user"] as? [String: Any])
        XCTAssertEqual(secondUser["isFirstLaunch"] as? String, "true", "the flag is not consumed by the first context build")
    }

    func testFirstLaunchIsReportedIntoTheContextAsAString() throws {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        let json: String = try XCTUnwrap(builder.buildContextJSON(resolvedTheme: .light, activeEntitlementIds: [], productsContext: [:]))
        let context: [String: Any] = try decodeContext(json)

        let user: [String: Any] = try XCTUnwrap(context["user"] as? [String: Any])
        XCTAssertEqual(user["isFirstLaunch"] as? String, "false")
    }

    // MARK: - Days since install

    func testDaysSinceInstallIsNeverNegative() {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        XCTAssertGreaterThanOrEqual(builder.calculateDaysSinceInstall(), 0)
    }

    func testDaysSinceInstallIsStableAcrossCalls() {
        let builder = NoCodesContextBuilder(isFirstLaunch: false)

        XCTAssertEqual(builder.calculateDaysSinceInstall(), builder.calculateDaysSinceInstall())
    }

    // MARK: - Private

    private func decodeContext(_ json: String) throws -> [String: Any] {
        let data: Data = Data(json.utf8)
        let wrapper: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        return try XCTUnwrap(wrapper["data"] as? [String: Any])
    }
}

// MARK: - The first-launch flag itself

final class NoCodesFirstLaunchTests: XCTestCase {

    private let storageKey = "io.qonversion.nocodes.alreadyLaunchedBefore"

    func testAnInstallThatNeverLaunchedBeforeIsAFirstLaunch() {
        let storage: UserDefaults = TestDefaults.makeIsolated()

        XCTAssertTrue(NoCodesFirstLaunch.resolve(storage: storage, daysSinceInstall: 0))
    }

    func testTheFlagIsLatchedSoLaterLaunchesAreNotFirstLaunches() {
        let storage: UserDefaults = TestDefaults.makeIsolated()

        XCTAssertTrue(NoCodesFirstLaunch.resolve(storage: storage, daysSinceInstall: 0))
        XCTAssertFalse(NoCodesFirstLaunch.resolve(storage: storage, daysSinceInstall: 0))
    }

    /// An app installed days ago that never reached this code is not starting
    /// for the first time, whatever the missing flag suggests.
    func testAnOlderInstallIsNotAFirstLaunchEvenWithoutTheFlag() {
        let storage: UserDefaults = TestDefaults.makeIsolated()

        XCTAssertFalse(NoCodesFirstLaunch.resolve(storage: storage, daysSinceInstall: 3))
        XCTAssertTrue(storage.bool(forKey: storageKey), "the flag is latched either way")
    }

    /// The production Objective-C SDK wrote this very key on the first screen
    /// it built a context for, so an upgraded install must keep its answer.
    func testALegacyFlagKeepsAnUpgradedInstallOutOfTheFirstLaunch() {
        let storage: UserDefaults = TestDefaults.makeIsolated()
        storage.set(true, forKey: storageKey)

        XCTAssertFalse(NoCodesFirstLaunch.resolve(storage: storage, daysSinceInstall: 0))
    }

    /// The flag belongs to the storage the SDK was given, not to the standard
    /// domain of the host app.
    func testTheFlagIsReadAndWrittenThroughTheGivenStorage() {
        let storage: UserDefaults = TestDefaults.makeIsolated()
        let other: UserDefaults = TestDefaults.makeIsolated()

        let _ = NoCodesFirstLaunch.resolve(storage: storage, daysSinceInstall: 0)

        XCTAssertTrue(storage.bool(forKey: storageKey))
        XCTAssertFalse(other.bool(forKey: storageKey))
    }
}
