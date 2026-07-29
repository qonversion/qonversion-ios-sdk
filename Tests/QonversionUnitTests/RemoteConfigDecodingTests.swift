//
//  RemoteConfigDecodingTests.swift
//  QonversionUnitTests
//
//  Decoding contract for Qonversion.RemoteConfig, its Source, the Experiment
//  it carries, and the context-key lookups on Qonversion.RemoteConfigList.
//

import XCTest
@testable import Qonversion

final class RemoteConfigDecodingTests: XCTestCase {

    private func decodeConfig(_ json: String) throws -> Qonversion.RemoteConfig {
        let decoder = JSONDecoder()
        return try decoder.decode(Qonversion.RemoteConfig.self, from: Data(json.utf8))
    }

    private func decodeList(_ json: String) throws -> Qonversion.RemoteConfigList {
        let decoder = JSONDecoder()
        return try decoder.decode(Qonversion.RemoteConfigList.self, from: Data(json.utf8))
    }

    // MARK: - context key normalization

    func testAnEmptyContextKeyDecodesToNil() throws {
        let json = #"{"payload": {"k": "v"}, "source": {"uid": "u1", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": ""}}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertNil(config.source?.contextKey, "an empty context key means the config is bound to none")
    }

    func testAnAbsentContextKeyDecodesToNil() throws {
        let json = #"{"payload": {"k": "v"}, "source": {"uid": "u1", "name": "n", "type": "remote_configuration", "assignment_type": "auto"}}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertNil(config.source?.contextKey)
    }

    func testLookupByAnEmptyStringFindsTheEmptyContextKeyConfig() throws {
        // The documented shape used to be an empty string, so hosts written
        // against it — and hosts migrating from the ObjC SDK — pass "".
        let json = """
        [
          {"payload": {"k": "empty"}, "source": {"uid": "u1", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": ""}},
          {"payload": {"k": "main"}, "source": {"uid": "u2", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": "main"}}
        ]
        """

        let list: Qonversion.RemoteConfigList = try decodeList(json)

        XCTAssertEqual(list.remoteConfig(for: "")?.source?.identifier, "u1")
        XCTAssertEqual(list.remoteConfigForEmptyContextKey()?.source?.identifier, "u1")
        XCTAssertEqual(list.remoteConfig(for: "main")?.source?.identifier, "u2")
    }

    func testAConfigWithoutASourceIsNotTheEmptyContextKeyConfig() throws {
        let json = """
        [
          {"payload": {"k": "unassigned"}, "source": null},
          {"payload": {"k": "empty"}, "source": {"uid": "u1", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": ""}}
        ]
        """

        let list: Qonversion.RemoteConfigList = try decodeList(json)

        XCTAssertEqual(list.remoteConfigForEmptyContextKey()?.source?.identifier, "u1",
                       "an unassigned config must not answer the empty-context-key lookup")
        XCTAssertEqual(list.remoteConfig(for: "")?.source?.identifier, "u1")
    }

    func testAListOfOnlyUnassignedConfigsHasNoEmptyContextKeyConfig() throws {
        let json = #"[{"payload": {"k": "unassigned"}, "source": null}]"#

        let list: Qonversion.RemoteConfigList = try decodeList(json)

        XCTAssertEqual(list.remoteConfigs.count, 1)
        XCTAssertNil(list.remoteConfigForEmptyContextKey())
    }

    // MARK: - tolerant Source decoding

    func testASourceWithoutAnAssignmentTypeKeepsTheConfig() throws {
        let json = #"{"payload": {"k": "v"}, "source": {"uid": "u1", "name": "n", "type": "remote_configuration", "context_key": "main"}}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.payload?["k"] as? String, "v", "one missing metadata key must not cost the payload")
        XCTAssertEqual(config.source?.contextKey, "main", "the context key must survive so the config still routes")
        XCTAssertEqual(config.source?.assignmentType, .unknown)
    }

    func testASourceWithoutATypeKeepsTheConfig() throws {
        let json = #"{"payload": {"k": "v"}, "source": {"uid": "u1", "name": "n", "assignment_type": "auto", "context_key": "main"}}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.source?.type, .unknown)
        XCTAssertEqual(config.source?.contextKey, "main")
    }

    func testASourceWithoutAUidOrNameKeepsTheConfig() throws {
        let json = #"{"payload": {"k": "v"}, "source": {"type": "remote_configuration", "assignment_type": "auto", "context_key": "main"}}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.source?.identifier, "")
        XCTAssertEqual(config.source?.name, "")
        XCTAssertEqual(config.source?.contextKey, "main")
    }

    func testAFullSourceStillDecodesEveryField() throws {
        let json = #"{"payload": {"k": "v"}, "source": {"uid": "u1", "name": "Main config", "type": "experiment_control_group", "assignment_type": "manual", "context_key": "main"}}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.source?.identifier, "u1")
        XCTAssertEqual(config.source?.name, "Main config")
        XCTAssertEqual(config.source?.type, .experimentControlGroup)
        XCTAssertEqual(config.source?.assignmentType, .manual)
        XCTAssertEqual(config.source?.contextKey, "main")
    }

    // MARK: - tolerant Experiment decoding

    func testAnExperimentWithoutAGroupTypeKeepsTheConfig() throws {
        let json = #"{"payload": {"k": "v"}, "experiment": {"uid": "e1", "name": "Exp", "group": {"uid": "g1", "name": "Group"}}, "source": null}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.experiment?.identifier, "e1")
        XCTAssertEqual(config.experiment?.group.identifier, "g1")
        XCTAssertEqual(config.experiment?.group.type, .unknown)
    }

    func testAnExperimentWithoutAGroupKeepsTheConfig() throws {
        let json = #"{"payload": {"k": "v"}, "experiment": {"uid": "e1", "name": "Exp"}, "source": null}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.payload?["k"] as? String, "v")
        XCTAssertEqual(config.experiment?.identifier, "e1")
        XCTAssertEqual(config.experiment?.group.type, .unknown)
    }

    func testAnExperimentWithoutAUidKeepsTheConfig() throws {
        let json = #"{"payload": {"k": "v"}, "experiment": {"name": "Exp", "group": {"uid": "g1", "name": "Group", "type": "treatment"}}, "source": null}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.experiment?.identifier, "")
        XCTAssertEqual(config.experiment?.group.type, .treatment)
    }

    func testAFullExperimentStillDecodesEveryField() throws {
        let json = #"{"payload": {"k": "v"}, "experiment": {"uid": "e1", "name": "Exp", "group": {"uid": "g1", "name": "Group", "type": "control"}}, "source": null}"#

        let config: Qonversion.RemoteConfig = try decodeConfig(json)

        XCTAssertEqual(config.experiment?.identifier, "e1")
        XCTAssertEqual(config.experiment?.name, "Exp")
        XCTAssertEqual(config.experiment?.group.identifier, "g1")
        XCTAssertEqual(config.experiment?.group.name, "Group")
        XCTAssertEqual(config.experiment?.group.type, .control)
    }
}
