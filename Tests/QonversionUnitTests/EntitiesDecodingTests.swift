//
//  EntitiesDecodingTests.swift
//  QonversionUnitTests
//
//  Fixation tests for entity decoding: locks in current behavior as-is,
//  using a decoder configured the same way as MiscAssembly.jsonDecoder().
//

import XCTest
@testable import Qonversion

final class EntitiesDecodingTests: XCTestCase {

    /// Mirrors MiscAssembly.jsonDecoder().
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - User

    func testUserDecodingMapsV4Fields() throws {
        let json = #"{"id": "QON_abc", "created_at": "2024-03-09T16:00:00Z", "identity_id": "ext_1", "environment": "prod"}"#

        let user = try decode(Qonversion.User.self, json)

        XCTAssertEqual(user.id, "QON_abc")
        XCTAssertEqual(user.creationDate, Date(timeIntervalSince1970: 1_709_999_400 + 600))
        XCTAssertEqual(user.identityId, "ext_1")
        XCTAssertEqual(user.environment, .production)
    }

    func testUserDecodingSandboxEnvironment() throws {
        let json = #"{"id": "QON_abc", "created_at": "2023-11-14T22:13:20Z", "environment": "sandbox"}"#

        let user = try decode(Qonversion.User.self, json)

        XCTAssertEqual(user.environment, .sandbox)
    }

    func testUserDecodingToleratesMissingOptionalFields() throws {
        // Only the id is required; created_at/identity_id/environment may be
        // absent (environment defaults to production).
        let json = #"{"id": "QON_abc"}"#

        let user = try decode(Qonversion.User.self, json)

        XCTAssertEqual(user.id, "QON_abc")
        XCTAssertNil(user.creationDate)
        XCTAssertNil(user.identityId)
        XCTAssertEqual(user.environment, .production)
    }

    func testUserDecodingToleratesUnknownEnvironment() throws {
        let json = #"{"id": "QON_abc", "created_at": "2023-11-14T22:13:20Z", "environment": "staging"}"#

        let user = try decode(Qonversion.User.self, json)

        XCTAssertEqual(user.environment, .production)
    }

    // MARK: - RemoteConfig

    private func remoteConfigJSON(
        payload: String = #"{"key": "value"}"#,
        experiment: String = "null",
        type: String = "remote_configuration",
        assignmentType: String = "auto",
        contextKeyFragment: String = #""context_key": "main""#
    ) -> String {
        """
        {
            "payload": \(payload),
            "experiment": \(experiment),
            "source": {
                "uid": "source_uid",
                "name": "Source name",
                "type": "\(type)",
                "assignment_type": "\(assignmentType)",
                \(contextKeyFragment)
            }
        }
        """
    }

    func testRemoteConfigDecodingWithMixedPayloadTypes() throws {
        let payload = #"{"string": "value", "int": 42, "double": 3.5, "bool": true, "nested": {"key": "v"}, "array": [1, 2], "null_key": null}"#
        let json = remoteConfigJSON(payload: payload)

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        let decodedPayload = try XCTUnwrap(remoteConfig.payload)
        XCTAssertEqual(decodedPayload["string"] as? String, "value")
        XCTAssertEqual(decodedPayload["int"] as? Int, 42)
        XCTAssertEqual(decodedPayload["double"] as? Double, 3.5)
        XCTAssertEqual(decodedPayload["bool"] as? Bool, true)
        XCTAssertEqual((decodedPayload["nested"] as? [String: Any])?["key"] as? String, "v")
        XCTAssertEqual(decodedPayload["array"] as? [Int], [1, 2])
        // Fixates current behavior: null payload values are kept as keys (wrapped nil), not dropped.
        XCTAssertTrue(decodedPayload.keys.contains("null_key"))
        XCTAssertNil(remoteConfig.experiment)
    }

    func testRemoteConfigDecodingSourceFieldsMapping() throws {
        let json = remoteConfigJSON(type: "experiment_control_group", assignmentType: "manual")

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        // "uid" maps to identifier, snake_case fields map to camelCase properties.
        XCTAssertEqual(remoteConfig.source?.identifier, "source_uid")
        XCTAssertEqual(remoteConfig.source?.name, "Source name")
        XCTAssertEqual(remoteConfig.source?.type, .experimentControlGroup)
        XCTAssertEqual(remoteConfig.source?.assignmentType, .manual)
        XCTAssertEqual(remoteConfig.source?.contextKey, "main")
    }

    func testRemoteConfigDecodesWithANullSource() throws {
        // The backend serializes source from a pointer without omitempty, so
        // an unassigned config arrives as an explicit null. That is a config
        // without a source, never a broken payload.
        let json = #"{"payload": {"key": "value"}, "experiment": null, "source": null}"#

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.source)
        XCTAssertEqual(remoteConfig.payload?["key"] as? String, "value")
    }

    func testRemoteConfigDecodesWithAMissingSource() throws {
        let json = #"{"payload": {"key": "value"}}"#

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.source)
    }

    func testRemoteConfigDecodingNullPayloadBecomesNil() throws {
        let json = remoteConfigJSON(payload: "null")

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.payload)
    }

    func testRemoteConfigSourceEmptyContextKeyBecomesNil() throws {
        // Fixates current behavior: empty context_key strings are normalized to nil.
        let json = remoteConfigJSON(contextKeyFragment: #""context_key": """#)

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.source?.contextKey)
    }

    func testRemoteConfigSourceNullContextKeyBecomesNil() throws {
        let json = remoteConfigJSON(contextKeyFragment: #""context_key": null"#)

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.source?.contextKey)
    }

    func testOneMalformedEntitlementDoesNotNullTheWholeList() throws {
        let json = """
        {
            "object": "list",
            "data": [
                {"id": "premium", "is_active": true},
                {"is_active": true},
                {"id": "basic", "is_active": false}
            ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let list = try decoder.decode(Qonversion.EntitlementsList.self, from: Data(json.utf8))

        XCTAssertEqual(list.data.map(\.id), ["premium", "basic"], "the malformed element degrades, the user's access list survives")
    }

    func testRemoteConfigSourceToleratesAMissingContextKey() throws {
        // An absent key must decode like an explicit null — production
        // payloads omit optional fields.
        let json = remoteConfigJSON(contextKeyFragment: #""ignored": null"#)

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.source?.contextKey)
    }


    func testRemoteConfigDecodingWithExperiment() throws {
        // The backend sends the experiment and its group identifier as "uid",
        // exactly like the remote config source does.
        let experiment = #"{"uid": "exp_1", "name": "Experiment", "group": {"name": "Control", "uid": "group_1", "type": "control"}}"#
        let json = remoteConfigJSON(experiment: experiment)

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        let decodedExperiment = try XCTUnwrap(remoteConfig.experiment)
        XCTAssertEqual(decodedExperiment.identifier, "exp_1")
        XCTAssertEqual(decodedExperiment.name, "Experiment")
        XCTAssertEqual(decodedExperiment.group.identifier, "group_1")
        XCTAssertEqual(decodedExperiment.group.name, "Control")
        XCTAssertEqual(decodedExperiment.group.type, .control)
    }

    func testUnknownRemoteConfigEnumValuesFallBackToUnknown() throws {
        let json = remoteConfigJSON(type: "brand_new_backend_type", assignmentType: "brand_new_assignment")

        let config = try JSONDecoder.qonversionTest.decode(Qonversion.RemoteConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.source?.type, .unknown)
        XCTAssertEqual(config.source?.assignmentType, .unknown)
    }

    func testUnknownExperimentGroupTypeFallsBackToUnknown() throws {
        let json = #"{"uid": "exp_3", "name": "Exp", "group": {"name": "G", "uid": "g1", "type": "brand_new_group_type"}}"#

        let experiment = try JSONDecoder.qonversionTest.decode(Qonversion.Experiment.self, from: Data(json.utf8))

        XCTAssertEqual(experiment.group.type, .unknown)
    }

    // MARK: - Experiment

    func testExperimentDecodingTreatmentGroup() throws {
        let json = #"{"uid": "exp_2", "name": "Exp", "group": {"name": "Treatment", "uid": "group_2", "type": "treatment"}}"#

        let experiment = try decode(Qonversion.Experiment.self, json)

        XCTAssertEqual(experiment.identifier, "exp_2")
        XCTAssertEqual(experiment.group.identifier, "group_2")
        XCTAssertEqual(experiment.group.type, .treatment)
    }

    func testExperimentDecodingRejectsTheSwiftPropertyNameAsKey() {
        // Regression: "identifier" is a Swift property name, never a wire key —
        // decoding it would mean the SDK is reading a payload the backend
        // does not send.
        let json = #"{"identifier": "exp_4", "name": "Exp", "group": {"name": "G", "identifier": "g", "type": "control"}}"#

        XCTAssertThrowsError(try decode(Qonversion.Experiment.self, json))
    }

    // MARK: - RemoteConfigList

    func testRemoteConfigListDecodesFromTheBareArrayTheApiAnswersWith() throws {
        // The wire shape of v4/remote-configs.
        let json = "[\(remoteConfigJSON())]"

        let list = try decode(Qonversion.RemoteConfigList.self, json)

        XCTAssertEqual(list.remoteConfigs.count, 1)
        XCTAssertEqual(list.remoteConfigs[0].source?.identifier, "source_uid")
    }

    func testRemoteConfigListSkipsAMalformedRowOfTheBareArray() throws {
        let json = "[\(remoteConfigJSON()), {\"source\": {}}]"

        let list = try decode(Qonversion.RemoteConfigList.self, json)

        XCTAssertEqual(list.remoteConfigs.count, 1)
    }

    func testRemoteConfigListStillDecodesFromTheKeyedWrapper() throws {
        let json = """
        {"remoteConfigs": [\(remoteConfigJSON())]}
        """

        let list = try decode(Qonversion.RemoteConfigList.self, json)

        XCTAssertEqual(list.remoteConfigs.count, 1)
        XCTAssertEqual(list.remoteConfigs[0].source?.identifier, "source_uid")
    }

    func testRemoteConfigListLookupByContextKeyAndEmptyContextKey() {
        let mainSource = Qonversion.RemoteConfig.Source(identifier: "rc_main", name: "Main", type: .remoteConfiguration, assignmentType: .auto, contextKey: "main")
        let emptySource = Qonversion.RemoteConfig.Source(identifier: "rc_empty", name: "Empty", type: .remoteConfiguration, assignmentType: .auto, contextKey: nil)
        let list = Qonversion.RemoteConfigList(remoteConfigs: [
            Qonversion.RemoteConfig(payload: nil, experiment: nil, source: mainSource),
            Qonversion.RemoteConfig(payload: nil, experiment: nil, source: emptySource)
        ])

        XCTAssertEqual(list.remoteConfig(for: "main")?.source?.identifier, "rc_main")
        XCTAssertNil(list.remoteConfig(for: "unknown"))
        XCTAssertEqual(list.remoteConfigForEmptyContextKey()?.source?.identifier, "rc_empty")
    }

    // MARK: - UserProperty

    func testUserPropertyDecodingAndDefinedKey() throws {
        let json = #"{"key": "_q_email", "value": "dev@qonversion.io"}"#

        let property = try decode(Qonversion.UserProperty.self, json)

        XCTAssertEqual(property.key, "_q_email")
        XCTAssertEqual(property.value, "dev@qonversion.io")
        XCTAssertEqual(property.definedKey, .email)
    }

    func testUserPropertyDefinedKeyFallsBackToCustom() throws {
        let json = #"{"key": "my_own_key", "value": "v"}"#

        let property = try decode(Qonversion.UserProperty.self, json)

        XCTAssertEqual(property.definedKey, .custom)
    }

    func testUserPropertyEncodeDecodeRoundtrip() throws {
        let property = Qonversion.UserProperty(key: "_q_name", value: "John")

        let data = try JSONEncoder().encode(property)
        let restored = try decoder.decode(Qonversion.UserProperty.self, from: data)

        XCTAssertEqual(restored, property)
    }

    // MARK: - UserProperties

    func testUserPropertiesSplitsDefinedAndCustomAndFlattensMaps() {
        let email = Qonversion.UserProperty(key: "_q_email", value: "dev@qonversion.io")
        let name = Qonversion.UserProperty(key: "_q_name", value: "John")
        let custom = Qonversion.UserProperty(key: "custom_key", value: "custom_value")
        let properties = Qonversion.UserProperties([email, name, custom])

        XCTAssertEqual(properties.properties, [email, name, custom])
        XCTAssertEqual(properties.definedProperties, [email, name])
        XCTAssertEqual(properties.customProperties, [custom])
        XCTAssertEqual(properties.flatPropertiesMap, ["_q_email": "dev@qonversion.io", "_q_name": "John", "custom_key": "custom_value"])
        XCTAssertEqual(properties.flatDefinedPropertiesMap, [.email: "dev@qonversion.io", .name: "John"])
        XCTAssertEqual(properties.flatCustomPropertiesMap, ["custom_key": "custom_value"])
        XCTAssertEqual(properties.property(for: "custom_key"), custom)
        XCTAssertNil(properties.property(for: "missing"))
        XCTAssertEqual(properties.definedProperty(for: .email), email)
        XCTAssertNil(properties.definedProperty(for: .appsFlyerUserId))
    }

    func testUserPropertiesDuplicateKeysKeepBothInListButLastWinsInMap() {
        let first = Qonversion.UserProperty(key: "dup", value: "first")
        let second = Qonversion.UserProperty(key: "dup", value: "second")
        let properties = Qonversion.UserProperties([first, second])

        // Fixates current behavior: lists keep duplicates, flattened maps keep the LAST value,
        // while property(for:) returns the FIRST match.
        XCTAssertEqual(properties.properties, [first, second])
        XCTAssertEqual(properties.customProperties, [first, second])
        XCTAssertEqual(properties.flatPropertiesMap["dup"], "second")
        XCTAssertEqual(properties.flatCustomPropertiesMap["dup"], "second")
        XCTAssertEqual(properties.property(for: "dup"), first)
    }

    // MARK: - Device

    private func makeDevice(model: String? = "iPhone15,2") -> Device {
        Device(
            manufacturer: "Apple",
            osName: "iOS",
            osVersion: "17.0",
            model: model,
            appVersion: "1.2.3",
            country: "US",
            language: "en",
            timezone: "America/New_York",
            advertisingId: nil,
            vendorId: "vendor-id",
            installDate: 1_700_000_000
        )
    }

    func testDeviceEquatable() {
        XCTAssertEqual(makeDevice(), makeDevice())
        XCTAssertNotEqual(makeDevice(model: "iPhone15,2"), makeDevice(model: "iPhone16,1"))
    }

    func testDeviceCodableRoundtrip() throws {
        let device = makeDevice()

        let data = try JSONEncoder().encode(device)
        let restored = try JSONDecoder().decode(Device.self, from: data)

        XCTAssertEqual(restored, device)
    }

    // MARK: - Entitlement

    func testEntitlementDecodesTheFullPayload() throws {
        let json = """
        {
            "id": "premium",
            "is_active": true,
            "source": "appstore",
            "started_at": "2024-01-01T00:00:00Z",
            "expires_at": "2024-02-01T00:00:00Z",
            "renews_count": 18,
            "trial_start_timestamp": "2023-12-25T00:00:00Z",
            "first_purchase_timestamp": "2024-01-01T00:00:00Z",
            "last_purchase_timestamp": "2024-01-20T00:00:00Z",
            "auto_renew_disable_timestamp": "2024-01-25T00:00:00Z",
            "last_activated_offer_code": "PROMO10",
            "grant_type": "offer_code",
            "product": {"product_id": "pro", "subscription": {"renew_state": "will_renew"}},
            "store_transactions": [
                {
                    "transaction_id": "tx_1",
                    "original_transaction_id": "otx_1",
                    "offer_code": "PROMO10",
                    "promo_offer_id": "promo_1",
                    "transaction_timestamp": "2024-01-01T00:00:00Z",
                    "expiration_timestamp": "2024-02-01T00:00:00Z",
                    "transaction_revoke_timestamp": "2024-01-15T00:00:00Z",
                    "environment": "sandbox",
                    "ownership_type": "family_shared",
                    "type": "trial_started"
                }
            ]
        }
        """

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.id, "premium")
        XCTAssertEqual(entitlement.renewsCount, 18)
        XCTAssertEqual(entitlement.trialStartDate, Date(timeIntervalSince1970: 1_703_462_400))
        XCTAssertEqual(entitlement.firstPurchaseDate, Date(timeIntervalSince1970: 1_704_067_200))
        XCTAssertEqual(entitlement.lastPurchaseDate, Date(timeIntervalSince1970: 1_705_708_800))
        XCTAssertEqual(entitlement.autoRenewDisableDate, Date(timeIntervalSince1970: 1_706_140_800))
        XCTAssertEqual(entitlement.lastActivatedOfferCode, "PROMO10")
        XCTAssertEqual(entitlement.grantType, .offerCode)
        XCTAssertEqual(entitlement.transactions.count, 1)

        let transaction = try XCTUnwrap(entitlement.transactions.first)
        XCTAssertEqual(transaction.transactionId, "tx_1")
        XCTAssertEqual(transaction.originalTransactionId, "otx_1")
        XCTAssertEqual(transaction.offerCode, "PROMO10")
        XCTAssertEqual(transaction.promoOfferId, "promo_1")
        XCTAssertEqual(transaction.transactionDate, Date(timeIntervalSince1970: 1_704_067_200))
        XCTAssertEqual(transaction.expirationDate, Date(timeIntervalSince1970: 1_706_745_600))
        XCTAssertEqual(transaction.revocationDate, Date(timeIntervalSince1970: 1_705_276_800))
        XCTAssertEqual(transaction.environment, .sandbox)
        XCTAssertEqual(transaction.ownershipType, .familyShared)
        XCTAssertEqual(transaction.type, .trialStarted)
    }

    func testStoreTransactionDecodesTheRealWireVocabulary() throws {
        // The exact strings the backend writes into store_transactions.
        let types: [(wire: String, expected: Qonversion.Entitlement.StoreTransaction.TransactionType)] = [
            ("subscription_started", .subscriptionStarted),
            ("subscription_renewed", .subscriptionRenewed),
            ("trial_started", .trialStarted),
            ("intro_started", .introStarted),
            ("intro_renewed", .introRenewed),
            ("non_consumable_purchase", .nonConsumablePurchase),
        ]

        for type in types {
            let json = "{\"id\": \"premium\", \"is_active\": true, \"store_transactions\": [{\"transaction_id\": \"tx\", \"type\": \"\(type.wire)\"}]}"
            let entitlement = try decode(Qonversion.Entitlement.self, json)

            XCTAssertEqual(entitlement.transactions.first?.type, type.expected, "type \(type.wire)")
        }

        let ownerships: [(wire: String, expected: Qonversion.Entitlement.StoreTransaction.OwnershipType)] = [
            ("owner", .owner),
            ("family_shared", .familyShared),
            // Tolerated alias: the grant_type vocabulary spells the same idea
            // "family_sharing", and an older payload may reuse it here.
            ("family_sharing", .familyShared),
        ]

        for ownership in ownerships {
            let json = "{\"id\": \"premium\", \"is_active\": true, \"store_transactions\": [{\"transaction_id\": \"tx\", \"ownership_type\": \"\(ownership.wire)\"}]}"
            let entitlement = try decode(Qonversion.Entitlement.self, json)

            XCTAssertEqual(entitlement.transactions.first?.ownershipType, ownership.expected, "ownership \(ownership.wire)")
        }

        for environment in [("sandbox", Qonversion.Entitlement.StoreTransaction.Environment.sandbox), ("production", .production)] {
            let json = "{\"id\": \"premium\", \"is_active\": true, \"store_transactions\": [{\"transaction_id\": \"tx\", \"environment\": \"\(environment.0)\"}]}"
            let entitlement = try decode(Qonversion.Entitlement.self, json)

            XCTAssertEqual(entitlement.transactions.first?.environment, environment.1, "environment \(environment.0)")
        }
    }

    func testTheMisspelledNonConsumableWireValueIsStillTolerated() throws {
        // The SDK guessed "nonconsumable_purchase" before the contract was
        // read off the backend; keep accepting it so a proxy that normalizes
        // to the old spelling does not degrade to .unknown.
        let json = #"{"id": "premium", "is_active": true, "store_transactions": [{"transaction_id": "tx", "type": "nonconsumable_purchase"}]}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.transactions.first?.type, .nonConsumablePurchase)
    }

    func testEntitlementDecodesTheMinimalPayload() throws {
        // Every added field is optional on the wire: the current backend does
        // not send them yet and the decode must not fail.
        let json = #"{"id": "premium", "is_active": true}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.id, "premium")
        XCTAssertEqual(entitlement.renewsCount, 0)
        XCTAssertNil(entitlement.trialStartDate)
        XCTAssertNil(entitlement.firstPurchaseDate)
        XCTAssertNil(entitlement.lastPurchaseDate)
        XCTAssertNil(entitlement.autoRenewDisableDate)
        XCTAssertNil(entitlement.lastActivatedOfferCode)
        XCTAssertEqual(entitlement.grantType, .purchase, "the production default")
        XCTAssertTrue(entitlement.transactions.isEmpty)
    }

    func testEntitlementUnknownEnumValuesFallBackToTheProductionDefaults() throws {
        let json = """
        {
            "id": "premium",
            "is_active": true,
            "grant_type": "brand_new_grant_type",
            "product": {"product_id": "pro", "subscription": {"renew_state": "brand_new_state"}},
            "store_transactions": [
                {"transaction_id": "tx_1", "environment": "brand_new_env", "ownership_type": "brand_new_owner", "type": "brand_new_type"}
            ]
        }
        """

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.grantType, .purchase)
        XCTAssertEqual(entitlement.renewState, .unknown)
        let transaction = try XCTUnwrap(entitlement.transactions.first)
        XCTAssertEqual(transaction.environment, .production)
        XCTAssertEqual(transaction.ownershipType, .owner)
        XCTAssertEqual(transaction.type, .unknown)
    }

    func testRenewStateDecodesTheThreeWireValues() throws {
        // will_renew | canceled | billing_issue is the whole wire vocabulary.
        let states: [(wire: String, expected: Qonversion.Entitlement.RenewState)] = [
            ("will_renew", .willRenew),
            ("canceled", .canceled),
            ("billing_issue", .billingIssue),
        ]

        for state in states {
            let json = "{\"id\": \"premium\", \"is_active\": true, \"source\": \"appstore\", \"product\": {\"product_id\": \"pro\", \"subscription\": {\"renew_state\": \"\(state.wire)\"}}}"
            let entitlement = try decode(Qonversion.Entitlement.self, json)

            XCTAssertEqual(entitlement.renewState, state.expected, "renew_state \(state.wire)")
        }
    }

    func testAnAbsentSubscriptionOnAKnownStoreSourceMeansNonRenewable() throws {
        // The backend has no "non_renewable" renew state: it expresses a
        // non-renewable purchase by omitting the subscription object
        // (product_center derivation rule).
        let sources: [String] = ["appstore", "playstore", "stripe"]

        for source in sources {
            let withoutSubscription = "{\"id\": \"lifetime\", \"is_active\": true, \"source\": \"\(source)\", \"product\": {\"product_id\": \"pro\"}}"
            let withoutProduct = "{\"id\": \"lifetime\", \"is_active\": true, \"source\": \"\(source)\"}"

            XCTAssertEqual(try decode(Qonversion.Entitlement.self, withoutSubscription).renewState, .nonRenewable, "source \(source)")
            XCTAssertEqual(try decode(Qonversion.Entitlement.self, withoutProduct).renewState, .nonRenewable, "source \(source)")
        }
    }

    func testAnAbsentSubscriptionOnAManualGrantMeansUnknown() throws {
        // A manual grant carries no store subscription at all, so its renew
        // state is genuinely unknown, not non-renewable.
        let json = #"{"id": "premium", "is_active": true, "source": "manual", "product": {"product_id": "pro"}}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.renewState, .unknown)
    }

    func testAnAbsentSubscriptionOnAnUnrecognizedSourceMeansUnknown() throws {
        // A store this SDK version does not know yet says nothing about
        // renewal, and no information must not become the affirmative claim
        // "this purchase never renews".
        let json = #"{"id": "premium", "is_active": true, "source": "brand_new_store", "product": {"product_id": "pro"}}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.source, .unknown)
        XCTAssertEqual(entitlement.renewState, .unknown)
    }

    func testAnExplicitNonRenewableStateIsHonoredWhereverItComesFrom() throws {
        // Two reasons to accept it although the current API does not send it:
        // caches written by an earlier build of this SDK put it into
        // product.subscription.renew_state, and honoring it beats degrading to
        // .unknown if the backend ever does name the state.
        let json = #"{"id": "lifetime", "is_active": true, "source": "manual", "product": {"product_id": "pro", "subscription": {"renew_state": "non_renewable"}}}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.renewState, .nonRenewable, "an explicit state wins over the derivation, which would have said .unknown here")
    }

    func testTheDerivedRenewStateSurvivesTheCacheRoundtrip() throws {
        // The entitlements cache round-trips through the same Codable. A
        // locally calculated entitlement has no renew state at all, and a
        // derived one must not be re-derived into something else on the way
        // back in.
        let cases: [(entitlement: Qonversion.Entitlement, expected: Qonversion.Entitlement.RenewState)] = [
            (Qonversion.Entitlement(id: "a", active: true, source: .appStore, renewState: .willRenew, productId: "pro"), .willRenew),
            (Qonversion.Entitlement(id: "b", active: true, source: .appStore, renewState: .canceled, productId: "pro"), .canceled),
            (Qonversion.Entitlement(id: "c", active: true, source: .appStore, renewState: .billingIssue, productId: "pro"), .billingIssue),
            (Qonversion.Entitlement(id: "d", active: true, source: .appStore, renewState: .nonRenewable, productId: "pro"), .nonRenewable),
            (Qonversion.Entitlement(id: "e", active: true, source: .manual, renewState: .unknown, productId: "pro"), .unknown),
            // The local calculation builds exactly this: an App Store source
            // with no renew state known.
            (Qonversion.Entitlement(id: "f", active: true, source: .appStore, productId: "pro"), .unknown),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for testCase in cases {
            let data: Data = try encoder.encode(testCase.entitlement)
            let restored = try decoder.decode(Qonversion.Entitlement.self, from: data)

            XCTAssertEqual(restored.renewState, testCase.expected, "entitlement \(testCase.entitlement.id)")
            XCTAssertEqual(restored.productId, testCase.entitlement.productId, "entitlement \(testCase.entitlement.id)")
            XCTAssertEqual(restored.source, testCase.entitlement.source, "entitlement \(testCase.entitlement.id)")
        }
    }

    func testTheDerivedStateSurvivesTheRealStorageEncoderAndDecoder() throws {
        // The round-trip above uses a hand-built encoder. This one goes
        // through the objects the SDK actually caches entitlements with —
        // MiscAssembly's encoder/decoder pair and LocalStorage — because a
        // strategy mismatch there is exactly how a cache field gets lost.
        let internalConfig = InternalConfig(userId: "")
        let miscAssembly = MiscAssembly(apiKey: "test-key", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)
        let encoder: JSONEncoder = miscAssembly.encoder()
        let storage: LocalStorage = miscAssembly.localStorage()
        // A locally calculated entitlement: an App Store source with no renew
        // state known, which the derivation alone would turn into
        // .nonRenewable on the way back in.
        let calculated = Qonversion.Entitlement(id: "premium", active: true, source: .appStore, productId: "pro")
        let entitlements: [String: Qonversion.Entitlement] = ["premium": calculated]

        try storage.set(entitlements, forKey: "entitlements")
        let restored = try XCTUnwrap(try storage.object(forKey: "entitlements", dataType: [String: Qonversion.Entitlement].self))

        XCTAssertEqual(restored["premium"]?.renewState, .unknown, "the resolved state, not one re-derived from the source")

        // ...and the key that carries it is really in the encoded bytes.
        let data: Data = try encoder.encode(calculated)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["sdk_renew_state"] as? String, "unknown")
    }

    func testTheCacheNeverWritesTheNonRenewableStateAsARenewState() throws {
        // Writing a "non_renewable" renew_state into the cache would invent a
        // value the backend contract does not have.
        let entitlement = Qonversion.Entitlement(id: "lifetime", active: true, source: .appStore, renewState: .nonRenewable, productId: "pro")

        let data: Data = try JSONEncoder().encode(entitlement)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let product = try XCTUnwrap(object["product"] as? [String: Any])

        XCTAssertNil(product["subscription"], "a non-renewable entitlement has no subscription object")
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("\"renew_state\"") ?? true)
    }

    func testMalformedExpirationDegradesTheFieldNotTheList() throws {
        // expires_at drives the stale-cache filter, and a strict decode of it
        // would drop the whole entitlement — and the user's access with it.
        let json = """
        {
            "object": "list",
            "data": [
                {"id": "premium", "is_active": true, "expires_at": "not-a-date", "started_at": 12},
                {"id": "basic", "is_active": true}
            ]
        }
        """

        let list = try decoder.decode(Qonversion.EntitlementsList.self, from: Data(json.utf8))

        XCTAssertEqual(list.data.map(\.id), ["premium", "basic"])
        XCTAssertNil(list.data.first?.expirationDate, "the unreadable date degrades to nil")
        XCTAssertEqual(list.data.first?.startedDate, Date(timeIntervalSince1970: 12), "a unix timestamp is accepted next to the ISO8601 form")
    }

    func testAnAllMalformedListIsASchemaBreakNotAnEmptyList() {
        // Decoding it as [] would let the caller persist emptiness over its
        // offline data instead of falling back.
        let json = """
        {"object": "list", "data": [{"no": "id"}, {"still": "no id"}]}
        """

        XCTAssertThrowsError(try decoder.decode(Qonversion.EntitlementsList.self, from: Data(json.utf8)))
    }

    func testAGenuinelyEmptyListDecodesEmpty() throws {
        let list = try decoder.decode(Qonversion.EntitlementsList.self, from: Data(#"{"object": "list", "data": []}"#.utf8))

        XCTAssertTrue(list.data.isEmpty)
    }

    func testMalformedNewFieldsDegradeToTheirDefaults() throws {
        let json = #"{"id": "premium", "is_active": true, "renews_count": "eighteen", "last_activated_offer_code": 42}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.renewsCount, 0)
        XCTAssertNil(entitlement.lastActivatedOfferCode)
    }

    func testAZeroTimestampMeansNoDateNotNineteenSeventy() throws {
        // The previous API generation writes 0 for "never": decoding it as a
        // real date would make a lifetime entitlement look long expired.
        // Decoded with the strategy the SDK installs, which accepts epochs.
        let json = #"{"id": "lifetime", "is_active": true, "expires_at": 0, "trial_start_timestamp": 0}"#
        let tolerantDecoder = JSONDecoder()
        tolerantDecoder.dateDecodingStrategy = .qonversionTolerant

        let entitlement = try tolerantDecoder.decode(Qonversion.Entitlement.self, from: Data(json.utf8))

        XCTAssertNil(entitlement.expirationDate)
        XCTAssertNil(entitlement.trialStartDate)
    }

    func testEntitlementDecodesEpochTimestamps() throws {
        // The keys are inherited from the previous API generation, where the
        // values were unix timestamps — both forms must decode.
        let json = #"{"id": "premium", "is_active": true, "trial_start_timestamp": 1703462400, "store_transactions": [{"transaction_id": "tx_1", "transaction_timestamp": 1704067200}]}"#

        let entitlement = try decode(Qonversion.Entitlement.self, json)

        XCTAssertEqual(entitlement.trialStartDate, Date(timeIntervalSince1970: 1_703_462_400))
        XCTAssertEqual(entitlement.transactions.first?.transactionDate, Date(timeIntervalSince1970: 1_704_067_200))
    }

    func testEntitlementCacheRoundtripKeepsTheNewFields() throws {
        // The entitlements cache round-trips through Codable: a field that
        // does not survive encoding is lost on every offline launch.
        let json = """
        {
            "id": "premium",
            "is_active": true,
            "source": "appstore",
            "renews_count": 3,
            "last_activated_offer_code": "PROMO10",
            "grant_type": "family_sharing",
            "trial_start_timestamp": "2023-12-25T00:00:00Z",
            "store_transactions": [{"transaction_id": "tx_1", "type": "subscription_renewed", "environment": "sandbox"}]
        }
        """
        let entitlement = try decode(Qonversion.Entitlement.self, json)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data: Data = try encoder.encode(entitlement)
        let restored = try decoder.decode(Qonversion.Entitlement.self, from: data)

        XCTAssertEqual(restored.renewsCount, 3)
        XCTAssertEqual(restored.lastActivatedOfferCode, "PROMO10")
        XCTAssertEqual(restored.grantType, .familySharing)
        XCTAssertEqual(restored.trialStartDate, entitlement.trialStartDate)
        XCTAssertEqual(restored.transactions.first?.transactionId, "tx_1")
        XCTAssertEqual(restored.transactions.first?.type, .subscriptionRenewed)
        XCTAssertEqual(restored.transactions.first?.environment, .sandbox)
    }

    // MARK: - Transaction.Offer

    func testLegacyOfferExistsOnlyWhenTheTransactionCarriesOfferData() {
        // Below iOS 17.2 the else branch returned a non-nil offer with a nil
        // id and a nil type for EVERY transaction — the host could not tell
        // an offer purchase from a regular one.
        XCTAssertFalse(Qonversion.Transaction.Offer.hasLegacyOfferData(id: nil, type: nil))
        XCTAssertTrue(Qonversion.Transaction.Offer.hasLegacyOfferData(id: "offer_1", type: nil))
        XCTAssertTrue(Qonversion.Transaction.Offer.hasLegacyOfferData(id: nil, type: .introductory))
        XCTAssertTrue(Qonversion.Transaction.Offer.hasLegacyOfferData(id: "offer_1", type: .promotional))
    }

    // MARK: - Product

    func testProductDecodingUsesV4Keys() throws {
        // v4 wire keys: id / apple_product_id; extra fields are ignored and the
        // store product stays unlinked.
        let json = #"{"id": "main", "apple_product_id": "com.app.main", "type": "subscription", "created_at": "2024-01-01T00:00:00Z"}"#

        let product = try decode(Qonversion.Product.self, json)

        XCTAssertEqual(product.qonversionId, "main")
        XCTAssertEqual(product.storeId, "com.app.main")
        XCTAssertFalse(product.isStoreProductLinked)
        XCTAssertNil(product.displayName)
        XCTAssertNil(product.price)
        XCTAssertFalse(product.isStoreProductLinked)
    }

    func testProductIgnoresAnOfferingIdOnTheWire() throws {
        // Offerings are gone platform-wide: the backend never answers
        // offering_id, and a stray one must not reach any SDK surface.
        let json = #"{"id": "main", "apple_product_id": "com.app.main", "offering_id": "offering_1"}"#

        let product = try decode(Qonversion.Product.self, json)
        let encoded = try JSONEncoder().encode(product)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(product.qonversionId, "main")
        XCTAssertEqual(product.storeId, "com.app.main")
        XCTAssertFalse(fields.keys.contains("offering_id"))
    }
}

// MARK: - tolerant decoding installed by the assembly

final class ToleratedDecodingTests: XCTestCase {

    /// The very decoder the SDK uses for both the network and the storage.
    private func sdkDecoder() -> JSONDecoder {
        let internalConfig = InternalConfig(userId: "u")
        let miscAssembly = MiscAssembly(apiKey: "key", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)

        return miscAssembly.jsonDecoder()
    }

    func testFractionalSecondsDateDecodes() throws {
        let json = #"{"id": "QON_abc", "created_at": "2026-07-27T10:00:00.123Z"}"#

        let user = try sdkDecoder().decode(Qonversion.User.self, from: Data(json.utf8))

        XCTAssertEqual(user.creationDate?.timeIntervalSince1970 ?? 0, 1_785_146_400.123, accuracy: 0.001)
    }

    func testPlainRfc3339DateStillDecodes() throws {
        let json = #"{"id": "QON_abc", "created_at": "2026-07-27T10:00:00Z"}"#

        let user = try sdkDecoder().decode(Qonversion.User.self, from: Data(json.utf8))

        XCTAssertEqual(user.creationDate, Date(timeIntervalSince1970: 1_785_146_400))
    }

    func testDateWithAnOffsetDecodes() throws {
        let json = #"{"id": "QON_abc", "created_at": "2026-07-27T12:00:00+02:00"}"#

        let user = try sdkDecoder().decode(Qonversion.User.self, from: Data(json.utf8))

        XCTAssertEqual(user.creationDate, Date(timeIntervalSince1970: 1_785_146_400))
    }

    func testEpochTimestampDateDecodes() throws {
        let json = #"{"id": "QON_abc", "created_at": 1785146400}"#

        let user = try sdkDecoder().decode(Qonversion.User.self, from: Data(json.utf8))

        XCTAssertEqual(user.creationDate, Date(timeIntervalSince1970: 1_785_146_400))
    }

    func testAnUnreadableDateStillFailsThatValue() {
        let json = #"{"id": "QON_abc", "created_at": "yesterday"}"#

        XCTAssertThrowsError(try sdkDecoder().decode(Qonversion.User.self, from: Data(json.utf8)))
    }

    // MARK: - originalAppVersion

    func testUserIgnoresAppleExtraOnTheWire() throws {
        // The backend does not serve apple_extra: originalAppVersion is read
        // from StoreKit on the device, so a stray field must not feed it.
        let json = #"{"id": "QON_abc", "apple_extra": {"original_application_version": "1.0.3"}}"#

        let user = try sdkDecoder().decode(Qonversion.User.self, from: Data(json.utf8))

        XCTAssertNil(user.originalAppVersion)
    }

    func testUserEncodingCarriesNoAppleExtra() throws {
        let user = Qonversion.User(id: "QON_abc", originalAppVersion: "1.0.3")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder.encode(user)) as? [String: Any])

        XCTAssertFalse(fields.keys.contains("apple_extra"))
    }

    func testUserOriginalAppVersionSurvivesTheStorageRoundtrip() throws {
        // The locally resolved version is persisted with the user, so a
        // cached user carries it without a second StoreKit read.
        let user = Qonversion.User(id: "QON_abc", originalAppVersion: "1.0.3")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let restored = try sdkDecoder().decode(Qonversion.User.self, from: try encoder.encode(user))

        XCTAssertEqual(restored.originalAppVersion, "1.0.3")
    }

    // MARK: - lossy lists

    func testUserPropertiesListSkipsMalformedRows() throws {
        let json = #"{"data": [{"key": "_q_email", "value": "dev@qonversion.io"}, {"key": "broken"}, {"key": "custom", "value": "v"}]}"#

        let list = try sdkDecoder().decode(ListEnvelope<Qonversion.UserProperty>.self, from: Data(json.utf8))

        XCTAssertEqual(list.data.map(\.key), ["_q_email", "custom"])
    }

    func testAnAllMalformedProductsListThrowsInsteadOfEmptyingTheCatalog() {
        let json = #"{"data": [{"no": "key"}, {"also": "broken"}]}"#

        XCTAssertThrowsError(try sdkDecoder().decode(ListEnvelope<Qonversion.UserProperty>.self, from: Data(json.utf8)))
    }

    func testAnEmptyDataArrayStillDecodes() throws {
        let list = try sdkDecoder().decode(ListEnvelope<Qonversion.UserProperty>.self, from: Data(#"{"data": []}"#.utf8))

        XCTAssertTrue(list.data.isEmpty)
    }

    func testAnAllMalformedRemoteConfigListThrows() {
        let json = #"{"remoteConfigs": [{"source": {}}, {"source": {}}]}"#

        XCTAssertThrowsError(try sdkDecoder().decode(Qonversion.RemoteConfigList.self, from: Data(json.utf8)))
    }

    func testRemoteConfigListSkipsMalformedRows() throws {
        let good = #"{"payload": null, "experiment": null, "source": {"uid": "s1", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": "main"}}"#
        let json = "{\"remoteConfigs\": [\(good), {\"source\": {}}]}"

        let list = try sdkDecoder().decode(Qonversion.RemoteConfigList.self, from: Data(json.utf8))

        XCTAssertEqual(list.remoteConfigs.map { $0.source?.identifier }, ["s1"])
    }
}
