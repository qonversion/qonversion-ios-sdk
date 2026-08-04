//
//  ContractWorld.swift
//  QonversionContractTests
//
//  The contract layer: the REAL object graph — assembly, managers, services,
//  network stack and decoders — talking to a REAL backend over a real socket.
//  Nothing is stubbed.
//
//  This is not a second copy of the unit or integration suites. Those prove the
//  SDK behaves correctly given a response of the agreed shape; this one proves
//  the backend still produces that shape. Only a test that decodes bytes the
//  backend actually sent can catch a contract drift, and a drift is exactly the
//  failure the SDK cannot recover from at runtime.
//
//  Skipped unless QON_CONTRACT_BASE_URL is set, so `swift test` stays a pure
//  offline run everywhere else.
//

import XCTest
@testable import Qonversion

// MARK: - Environment

struct ContractEnvironment {

    let baseURL: String
    let apiKey: String
    /// A user seeded with entitlements of known provenance by the local stack's
    /// seeder — the only user whose entitlement response is predictable.
    let fixtureUserId: String
    let experimentId: String
    let experimentGroupId: String
    let remoteConfigId: String
    /// The App Store product id the fixture user's subscription was bought for.
    let purchaseProductStoreId: String

    /// Reads the environment, or skips the test when the stack is not
    /// configured. Skipping rather than failing keeps the offline `swift test`
    /// run green for everyone who is not pointing at a backend.
    static func current() throws -> ContractEnvironment {
        let environment = ProcessInfo.processInfo.environment
        guard let baseURL = environment["QON_CONTRACT_BASE_URL"], !baseURL.isEmpty else {
            throw XCTSkip("""
                QON_CONTRACT_BASE_URL is not set — the contract suite needs a running backend.
                Run it through dev/tests/integration/v4sdk/run-sdk-contract.sh, which brings up \
                the fixtures and points the SDK at the local gateway.
                """)
        }
        guard let apiKey = environment["QON_CONTRACT_API_KEY"], !apiKey.isEmpty else {
            throw XCTSkip("QON_CONTRACT_API_KEY is not set")
        }

        return ContractEnvironment(
            baseURL: baseURL,
            apiKey: apiKey,
            fixtureUserId: environment["QON_CONTRACT_FIXTURE_UID"] ?? "QON_itest_fixture_user",
            experimentId: environment["QON_CONTRACT_EXPERIMENT_ID"] ?? "11111111-1111-4111-8111-111111111111",
            experimentGroupId: environment["QON_CONTRACT_EXPERIMENT_GROUP"] ?? "ittreat1",
            remoteConfigId: environment["QON_CONTRACT_REMOTE_CONFIG_ID"] ?? "22222222-2222-4222-8222-222222222222",
            purchaseProductStoreId: environment["QON_CONTRACT_PRODUCT_STORE_ID"] ?? "com.qonversion.itest.p02"
        )
    }
}

// MARK: - The SDK under test

/// One SDK install pointed at the live backend.
///
/// Every instance gets its own UserDefaults suite, so each test starts as a
/// fresh install with a freshly generated uid — the same thing that happens on
/// a real first launch, and the reason tests never collide over user state.
final class ContractWorld {

    let environment: ContractEnvironment
    let assembly: QonversionAssembly
    private let suiteName: String
    private let userDefaults: UserDefaults

    let userService: UserServiceInterface
    let productsService: ProductsServiceInterface
    let entitlementsService: EntitlementsServiceInterface
    let deviceService: DeviceServiceInterface
    let purchasesService: PurchasesServiceInterface
    let remoteConfigService: RemoteConfigServiceInterface
    let userPropertiesManager: UserPropertiesManagerInterface

    init(environment: ContractEnvironment, launchMode: Qonversion.LaunchMode = .subscriptionManagement) throws {
        self.environment = environment

        suiteName = "qonversion.contract.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            throw ContractError("could not create the UserDefaults suite \(suiteName)")
        }
        userDefaults = suite

        // Built through Configuration rather than by handing the assembly a raw
        // string: `proxyURL` is a supported production setting, and its
        // normalization (scheme, trailing slash) is part of what the SDK does
        // with it. Passing the string straight to the assembly skips that step
        // and every request goes to a URL no route can match.
        let configuration = Qonversion.Configuration(
            apiKey: environment.apiKey,
            launchMode: launchMode,
            proxyURL: environment.baseURL,
            userDefaults: suite
        )
        assembly = QonversionAssembly(
            apiKey: configuration.apiKey,
            userDefaults: suite,
            launchMode: configuration.launchMode,
            baseURL: configuration.baseURL
        )

        userService = assembly.servicesAssembly.userService()
        productsService = assembly.servicesAssembly.productsService()
        entitlementsService = assembly.servicesAssembly.entitlementsService()
        deviceService = assembly.servicesAssembly.deviceService()
        purchasesService = assembly.servicesAssembly.purchasesService()
        remoteConfigService = assembly.servicesAssembly.remoteConfigService()
        userPropertiesManager = assembly.userPropertiesManager()
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    /// The uid this install generated, as the SDK stored it.
    var userId: String {
        userDefaults.string(forKey: UserServiceStorageKeys.userIdKey.rawValue) ?? ""
    }
}

struct ContractError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - The "no unknown" rule

/// Fails when a decoded enum landed on its `unknown` case.
///
/// Every one of these enums has an `unknown` member so that a value this SDK
/// version does not recognise degrades instead of crashing an app in
/// production. That tolerance is right at runtime and wrong in a contract test:
/// it is precisely what lets a renamed or retyped backend value pass unnoticed.
/// `source: "app_store"` instead of `"appstore"` would decode, land on
/// `.unknown`, and every assertion about the entitlement's provenance would
/// still hold — which is how a broken contract ships.
///
/// So here `unknown` is never an acceptable answer: the backend is expected to
/// speak only values this SDK knows.
func assertKnown<T: Equatable>(
    _ value: T,
    _ unknown: T,
    _ label: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertNotEqual(
        value, unknown,
        "\(label) decoded as .unknown — the backend sent a value this SDK version does not know",
        file: file, line: line
    )
}

/// Walks every enum an entitlement carries whose value comes off the wire, so a
/// new vocabulary value anywhere in the payload surfaces as a failure rather
/// than as a silently degraded field.
///
/// `renewState` is the one exception, and only for a manual grant. It is not
/// decoded from the response at all: the backend sends a renew state only
/// inside `product.subscription`, which a hand-granted entitlement has none of,
/// so the SDK derives the state from the source — and deliberately derives
/// `.unknown` rather than `.nonRenewable`, because "this entitlement never
/// renews" would be an affirmative claim nobody made. Enforcing the rule there
/// would fail on correct behaviour. It stays enforced for every store-backed
/// entitlement, where a renew state is genuinely expected on the wire.
func assertNoUnknownEnums(
    in entitlement: Qonversion.Entitlement,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertKnown(entitlement.source, .unknown, "entitlement(\(entitlement.id)).source", file: file, line: line)

    if entitlement.grantType != .manual {
        assertKnown(entitlement.renewState, .unknown, "entitlement(\(entitlement.id)).renewState", file: file, line: line)
    }

    for transaction in entitlement.transactions {
        let label = "entitlement(\(entitlement.id)).transaction(\(transaction.transactionId ?? "nil")).type"
        assertKnown(transaction.type, .unknown, label, file: file, line: line)
    }
}
