//
//  ContractTests.swift
//  QonversionContractTests
//
//  One test per /v4 route the SDK calls. Each drives the SDK's own service
//  layer, so the request is built by production code and the response is
//  decoded by production decoders — the assertions are about what the SDK ends
//  up holding, not about raw JSON.
//

import XCTest
@testable import Qonversion

final class ContractTests: XCTestCase {

    private var environment: ContractEnvironment!

    override func setUpWithError() throws {
        try super.setUpWithError()
        environment = try ContractEnvironment.current()
    }

    private func newWorld() throws -> ContractWorld {
        try ContractWorld(environment: environment)
    }

    // MARK: - Users

    /// POST /v4/users, then GET /v4/users/{id}.
    func testCreateAndFetchUser() async throws {
        let world = try newWorld()

        let created: Qonversion.User = try await world.userService.createUser()

        XCTAssertFalse(world.userId.isEmpty, "the SDK stored no uid after creating the user")
        XCTAssertEqual(created.id, world.userId, "the backend answered with a different uid than the SDK asked for")
        // The decoder swallows a date it cannot parse into nil, so a changed
        // created_at format would show up here and nowhere else.
        XCTAssertNotNil(created.creationDate, "created_at did not decode — the SDK cannot tell how old the install is")
        // The SDK sends no environment; the backend decides. Sandbox leaking in
        // would route live traffic into test data.
        XCTAssertEqual(created.environment, .production)

        let fetched: Qonversion.User = try await world.userService.user()
        XCTAssertEqual(fetched.id, created.id)
        XCTAssertEqual(fetched.identityId, created.identityId)
    }

    /// The upgrade-from-the-previous-SDK path: the uid already exists, the
    /// backend answers 422 already_exists, and createUser() has to recover by
    /// fetching instead of failing the launch. Worth exercising against the real
    /// backend because the recovery keys on the API error code in the body.
    func testCreateUserRecoversFromAlreadyExists() async throws {
        let world = try newWorld()

        let first: Qonversion.User = try await world.userService.createUser()
        let second: Qonversion.User = try await world.userService.createUser()

        XCTAssertEqual(second.id, first.id, "the already_exists recovery returned a different user")
    }

    // MARK: - Identities

    /// POST /v4/identities and GET /v4/identities/{id} with an email, which is
    /// what integrators overwhelmingly pass to identify().
    func testIdentityRoundTripWithAnEmail() async throws {
        let world = try newWorld()
        let user: Qonversion.User = try await world.userService.createUser()
        let email = "itest+\(UUID().uuidString.prefix(8))@example.com"

        let identifiedUserId: String = try await world.userService.createIdentity(externalId: email, userId: user.id)
        XCTAssertEqual(identifiedUserId, user.id)

        let resolved: String? = try await world.userService.identity(for: email)
        XCTAssertEqual(resolved, user.id, "the identity did not resolve back to the user it was created for")
    }

    /// An unknown external id must read as "no such identity", not as an error:
    /// identify() branches on nil to create the identity instead.
    func testUnknownIdentityResolvesToNil() async throws {
        let world = try newWorld()

        let resolved: String? = try await world.userService.identity(for: "itest-absent-\(UUID().uuidString.prefix(8))")

        XCTAssertNil(resolved)
    }

    // MARK: - Catalog

    /// GET /v4/entitlements, as the SDK consumes it: the definitions come back
    /// keyed by entitlement, and the SDK inverts them into product ->
    /// entitlements it unlocks.
    ///
    /// The SDK asks once, with no paging parameters, and ignores has_more. The
    /// seeder links 25 product/entitlement pairs — more than the dashboard page
    /// size — so a listing that came back truncated shows up here as products
    /// missing from the mapping, which at runtime means a bought product
    /// unlocking nothing.
    func testProductPermissionsCoverTheWholeCatalog() async throws {
        let world = try newWorld()

        let permissions: [String: [String]] = try await world.productsService.productPermissions()

        XCTAssertGreaterThanOrEqual(
            permissions.count, 25,
            "only \(permissions.count) products carry entitlements — the definitions listing is being paginated"
        )
        XCTAssertEqual(
            permissions["itest_prod_02"], ["itest_ent_02"],
            "the seeded product does not map to the entitlement it unlocks"
        )
    }

    // MARK: - Entitlements

    /// GET /v4/users/{uid}/entitlements for the seeded fixture user.
    ///
    /// Two entitlements of deliberately different provenance: one granted by
    /// hand, one backed by a subscription whose transactions the backend stored
    /// itself — the transaction-native case, where no receipt exists.
    func testFixtureUserEntitlementsDecodeFully() async throws {
        let world = try newWorld()

        let entitlements: [Qonversion.Entitlement] = try await world.entitlementsService
            .entitlements(userId: environment.fixtureUserId)

        for entitlement in entitlements {
            assertNoUnknownEnums(in: entitlement)
        }

        let byId: [String: Qonversion.Entitlement] = Dictionary(
            entitlements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        let manual: Qonversion.Entitlement = try XCTUnwrap(
            byId["itest_ent_01"], "the manually granted entitlement is missing — re-run the seeder"
        )
        XCTAssertTrue(manual.active)
        XCTAssertEqual(manual.source, .manual)
        XCTAssertEqual(manual.grantType, .manual)
        XCTAssertEqual(manual.renewsCount, 0)
        XCTAssertTrue(manual.transactions.isEmpty, "a hand-granted entitlement reported store transactions")

        let purchased: Qonversion.Entitlement = try XCTUnwrap(
            byId["itest_ent_02"], "the purchase-backed entitlement is missing — re-run the seeder"
        )
        XCTAssertTrue(purchased.active)
        XCTAssertEqual(purchased.source, .appStore)
        XCTAssertEqual(purchased.grantType, .purchase)
        // Two paid transactions out of three: a renewal is the second paid event.
        XCTAssertEqual(purchased.renewsCount, 1)
        XCTAssertNotNil(purchased.trialStartDate, "trial_start_timestamp did not reach the SDK")
        XCTAssertNotNil(purchased.firstPurchaseDate, "first_purchase_timestamp did not reach the SDK")
        XCTAssertNotNil(purchased.lastPurchaseDate, "last_purchase_timestamp did not reach the SDK")
        XCTAssertEqual(purchased.productId, "itest_prod_02")

        XCTAssertEqual(purchased.transactions.count, 3, "the stored transaction history did not reach the SDK")
        XCTAssertEqual(
            purchased.transactions.map(\.type),
            [.trialStarted, .subscriptionStarted, .subscriptionRenewed],
            "the transaction types or their order changed"
        )
    }

    /// A user with nothing bought must decode as an empty list, not as an error
    /// — that is the state of every install before its first purchase.
    func testFreshUserHasNoEntitlements() async throws {
        let world = try newWorld()
        let user: Qonversion.User = try await world.userService.createUser()

        let entitlements: [Qonversion.Entitlement] = try await world.entitlementsService.entitlements(userId: user.id)

        XCTAssertTrue(entitlements.isEmpty)
    }

    // MARK: - User properties

    /// POST then GET /v4/users/{uid}/properties. The two answer deliberately
    /// different shapes, and the SDK decodes both.
    func testUserPropertiesRoundTrip() async throws {
        let world = try newWorld()
        _ = try await world.userService.createUser()

        world.userPropertiesManager.setCustomUserProperty(key: "itest_contract_key", value: "itest_value")
        try await world.userPropertiesManager.sendProperties(force: true)

        let properties: Qonversion.UserProperties = try await world.userPropertiesManager.userProperties()

        let stored = properties.properties.first { $0.key == "itest_contract_key" }
        XCTAssertEqual(stored?.value, "itest_value", "the property did not come back from the backend")
    }

    // MARK: - Device

    /// POST and PUT /v4/users/{uid}/device.
    ///
    /// The wire contract is an exact echo, and the SDK compares what came back
    /// with what it sent to decide whether the record needs updating — so a
    /// dropped or retyped field silently turns into a device update on every
    /// single launch.
    func testDeviceCreateAndUpdateEcho() async throws {
        let world = try newWorld()
        _ = try await world.userService.createUser()

        let device = Device(
            osName: "iOS",
            osVersion: "17.4",
            model: "iPhone15,2",
            appVersion: "1.2.3",
            country: "US",
            language: "en",
            advertisingId: "00000000-0000-0000-0000-00000000ABCD",
            vendorId: "VEN-\(UUID().uuidString.prefix(8))",
            installDate: 1_700_000_000
        )

        let created: Device = try await world.deviceService.create(device: device)
        XCTAssertEqual(created, device, "POST /device did not echo the request back unchanged")

        let updated = Device(
            osName: device.osName,
            osVersion: "17.5",
            model: device.model,
            appVersion: "1.2.4",
            country: "GB",
            language: device.language,
            advertisingId: device.advertisingId,
            vendorId: device.vendorId,
            installDate: device.installDate
        )
        let echoed: Device = try await world.deviceService.update(device: updated)
        XCTAssertEqual(echoed, updated, "PUT /device did not echo the request back unchanged")
    }

    // MARK: - Purchases

    /// POST /v4/users/{uid}/purchases with a transaction the store cannot
    /// confirm.
    ///
    /// The local stack has no App Store credentials, so the happy path is out of
    /// reach here — what is in reach, and what matters more, is that the failure
    /// stays retryable. The SDK drops a purchase from its offline queue on a
    /// 4xx, so a premature terminal answer loses revenue with no way back.
    func testUnconfirmablePurchaseFailsRetryably() async throws {
        let world = try newWorld()
        let user: Qonversion.User = try await world.userService.createUser()

        let transaction = Qonversion.Transaction(
            id: "9\(UInt64.random(in: 100_000_000_000_000...999_999_999_999_999))",
            originalId: "9000000000000001",
            productId: environment.purchaseProductStoreId,
            purchaseDate: Date(),
            jws: "eyJhbGciOiJFUzI1NiJ9.eyJpdGVzdCI6dHJ1ZX0.signature"
        )

        do {
            _ = try await world.purchasesService.send(transaction, userId: user.id, trigger: .purchase)
            XCTFail("a transaction the store cannot confirm was accepted")
        } catch {
            let qonversionError = try XCTUnwrap(error as? QonversionError)
            XCTAssertEqual(
                qonversionError.type, .purchaseReportingFailed,
                "the SDK mapped the failure to \(qonversionError.type) instead of a reporting failure"
            )
        }
    }

    /// POST /v4/users/{uid}/offers/{offer_id}/signatures.
    ///
    /// "Not eligible" is the backend's verdict on the offer, not a transport
    /// failure, and the SDK has to keep the two apart: the host app shows a
    /// different thing in each case.
    func testPromotionalOfferIneligibilityIsItsOwnError() async throws {
        let world = try newWorld()
        let user: Qonversion.User = try await world.userService.createUser()

        do {
            _ = try await world.purchasesService.promotionalOffer(
                userId: user.id,
                offerId: "itest_offer",
                productStoreId: environment.purchaseProductStoreId
            )
            XCTFail("a user with no purchase history was found eligible for a promotional offer")
        } catch {
            let qonversionError = try XCTUnwrap(error as? QonversionError)
            XCTAssertEqual(
                qonversionError.type, .promoOfferNotEligible,
                "ineligibility arrived as \(qonversionError.type), which the host app cannot tell from a network failure"
            )
        }
    }

    // MARK: - Experiments and remote configurations

    /// POST and DELETE /v4/experiments/{experiment_id}/users/{user_id}.
    func testExperimentAttachAndDetach() async throws {
        let world = try newWorld()
        _ = try await world.userService.createUser()

        try await world.remoteConfigService.attachUserToExperiment(
            id: environment.experimentId,
            groupId: environment.experimentGroupId
        )
        try await world.remoteConfigService.detachUserFromExperiment(id: environment.experimentId)
    }

    /// POST and DELETE /v4/remote-configurations/{config_id}/users/{user_id}.
    func testRemoteConfigAttachAndDetach() async throws {
        let world = try newWorld()
        _ = try await world.userService.createUser()

        try await world.remoteConfigService.attachUserToRemoteConfig(id: environment.remoteConfigId)
        try await world.remoteConfigService.detachUserFromRemoteConfig(id: environment.remoteConfigId)
    }
}
