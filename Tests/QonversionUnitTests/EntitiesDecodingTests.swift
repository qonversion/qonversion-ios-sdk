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
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - User

    func testUserDecodingMapsCreatedToCreationDate() throws {
        let json = #"{"id": "QON_abc", "created": 1710000000, "environment": "production"}"#

        let user = try decode(Qonversion.User.self, json)

        XCTAssertEqual(user.id, "QON_abc")
        XCTAssertEqual(user.creationDate, Date(timeIntervalSince1970: 1_710_000_000))
        XCTAssertEqual(user.environment, .production)
    }

    func testUserDecodingSandboxEnvironment() throws {
        let json = #"{"id": "QON_abc", "created": 1700000000, "environment": "sandbox"}"#

        let user = try decode(Qonversion.User.self, json)

        XCTAssertEqual(user.environment, .sandbox)
    }

    func testUserDecodingFailsWhenEnvironmentIsMissing() {
        // Fixates current behavior: all User fields are required — the custom
        // init(from:) uses decode, not decodeIfPresent, for every field.
        let json = #"{"id": "QON_abc", "created": 1700000000}"#

        XCTAssertThrowsError(try decode(Qonversion.User.self, json))
    }

    func testUserDecodingFailsForUnknownEnvironment() {
        let json = #"{"id": "QON_abc", "created": 1700000000, "environment": "staging"}"#

        XCTAssertThrowsError(try decode(Qonversion.User.self, json))
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
        XCTAssertEqual(remoteConfig.source.identifier, "source_uid")
        XCTAssertEqual(remoteConfig.source.name, "Source name")
        XCTAssertEqual(remoteConfig.source.type, .experimentControlGroup)
        XCTAssertEqual(remoteConfig.source.assignmentType, .manual)
        XCTAssertEqual(remoteConfig.source.contextKey, "main")
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

        XCTAssertNil(remoteConfig.source.contextKey)
    }

    func testRemoteConfigSourceNullContextKeyBecomesNil() throws {
        let json = remoteConfigJSON(contextKeyFragment: #""context_key": null"#)

        let remoteConfig = try decode(Qonversion.RemoteConfig.self, json)

        XCTAssertNil(remoteConfig.source.contextKey)
    }

    func testRemoteConfigSourceDecodingFailsWhenContextKeyIsMissing() {
        // Fixates current behavior: Source.init(from:) uses decode(String?.self),
        // which requires the context_key key to be PRESENT (null is fine, absence is not).
        let json = remoteConfigJSON(contextKeyFragment: #""ignored": null"#)

        XCTAssertThrowsError(try decode(Qonversion.RemoteConfig.self, json))
    }


    func testRemoteConfigDecodingWithExperiment() throws {
        // Fixates current behavior: Experiment has NO custom CodingKeys, so JSON
        // must use Swift property names ("identifier", not "uid"/snake_case).
        let experiment = #"{"identifier": "exp_1", "name": "Experiment", "group": {"name": "Control", "identifier": "group_1", "type": "control"}}"#
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

        XCTAssertEqual(config.source.type, .unknown)
        XCTAssertEqual(config.source.assignmentType, .unknown)
    }

    func testUnknownExperimentGroupTypeFallsBackToUnknown() throws {
        let json = #"{"identifier": "exp_3", "name": "Exp", "group": {"name": "G", "identifier": "g1", "type": "brand_new_group_type"}}"#

        let experiment = try JSONDecoder.qonversionTest.decode(Qonversion.Experiment.self, from: Data(json.utf8))

        XCTAssertEqual(experiment.group.type, .unknown)
    }

    // MARK: - Experiment

    func testExperimentDecodingTreatmentGroup() throws {
        let json = #"{"identifier": "exp_2", "name": "Exp", "group": {"name": "Treatment", "identifier": "group_2", "type": "treatment"}}"#

        let experiment = try decode(Qonversion.Experiment.self, json)

        XCTAssertEqual(experiment.group.type, .treatment)
    }

    // MARK: - RemoteConfigList

    func testRemoteConfigListDecodesFromCamelCaseWrapperKey() throws {
        // Fixates current behavior: RemoteConfigList's Decodable conformance is
        // synthesized (vestigial) and expects a "remoteConfigs" camelCase key —
        // not a bare array and not snake_case.
        let json = """
        {"remoteConfigs": [\(remoteConfigJSON())]}
        """

        let list = try decode(Qonversion.RemoteConfigList.self, json)

        XCTAssertEqual(list.remoteConfigs.count, 1)
        XCTAssertEqual(list.remoteConfigs[0].source.identifier, "source_uid")
    }

    func testRemoteConfigListLookupByContextKeyAndEmptyContextKey() {
        let mainSource = Qonversion.RemoteConfig.Source(identifier: "rc_main", name: "Main", type: .remoteConfiguration, assignmentType: .auto, contextKey: "main")
        let emptySource = Qonversion.RemoteConfig.Source(identifier: "rc_empty", name: "Empty", type: .remoteConfiguration, assignmentType: .auto, contextKey: nil)
        let list = Qonversion.RemoteConfigList(remoteConfigs: [
            Qonversion.RemoteConfig(payload: nil, experiment: nil, source: mainSource),
            Qonversion.RemoteConfig(payload: nil, experiment: nil, source: emptySource)
        ])

        XCTAssertEqual(list.remoteConfig(for: "main")?.source.identifier, "rc_main")
        XCTAssertNil(list.remoteConfig(for: "unknown"))
        XCTAssertEqual(list.remoteConfigForEmptyContextKey()?.source.identifier, "rc_empty")
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

    // MARK: - Product

    func testProductDecodingUsesCamelCaseIdentityKeysOnly() throws {
        // Fixates current behavior: Product CodingKeys are camelCase Swift names
        // (no snake_case mapping) and only the identity fields participate;
        // any extra JSON fields are ignored and skProduct stays nil.
        let json = #"{"qonversionId": "main", "storeId": "com.app.main", "offeringId": "offering_1", "displayName": "ignored", "price": 9.99}"#

        let product = try decode(Qonversion.Product.self, json)

        XCTAssertEqual(product.qonversionId, "main")
        XCTAssertEqual(product.storeId, "com.app.main")
        XCTAssertEqual(product.offeringId, "offering_1")
        XCTAssertNil(product.skProduct)
        XCTAssertNil(product.displayName)
        XCTAssertNil(product.price)
        XCTAssertFalse(product.isStoreProductLinked)
    }

    func testProductDecodesWithNullOfferingId() throws {
        // A product outside any offering is valid: offeringId is optional.
        let json = #"{"qonversionId": "main", "storeId": "com.app.main", "offeringId": null}"#

        let product = try decode(Qonversion.Product.self, json)

        XCTAssertNil(product.offeringId)
    }

    func testProductDecodesWithMissingOfferingId() throws {
        let json = #"{"qonversionId": "main", "storeId": "com.app.main"}"#

        let product = try decode(Qonversion.Product.self, json)

        XCTAssertNil(product.offeringId)
    }
}
