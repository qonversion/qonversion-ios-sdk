//
//  RemoteConfigServiceTests.swift
//  QonversionUnitTests
//
//  Fixation tests for RemoteConfigService: locks in current behavior as-is.
//

import XCTest
@testable import Qonversion

final class RemoteConfigServiceTests: XCTestCase {

    private let userId = "QON_rc_user"

    // MARK: - Helpers

    private func makeService(processor: MockRequestProcessor) -> RemoteConfigService {
        RemoteConfigService(
            requestProcessor: processor,
            userIdProvider: InternalConfig(userId: userId),
            logger: LoggerWrapper()
        )
    }

    private func makeRemoteConfig(identifier: String = "rc_1", contextKey: String? = nil) -> Qonversion.RemoteConfig {
        let source = Qonversion.RemoteConfig.Source(
            identifier: identifier,
            name: "Remote config " + identifier,
            type: .remoteConfiguration,
            assignmentType: .auto,
            contextKey: contextKey
        )
        return Qonversion.RemoteConfig(payload: ["key": "value"], experiment: nil, source: source)
    }

    private func assertThrows(
        _ expectedType: QonversionErrorType,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, expectedType, file: file, line: line)
            XCTAssertEqual(error.error as? MockError, .stubbed, file: file, line: line)
        } catch {
            XCTFail("Expected QonversionError, got \(error)", file: file, line: line)
        }
    }

    // MARK: - loadRemoteConfig

    func testLoadRemoteConfigSendsRemoteConfigRequestWithContextKey() async throws {
        let processor = MockRequestProcessor()
        processor.results = [makeRemoteConfig(identifier: "rc_main", contextKey: "main")]
        let service = makeService(processor: processor)

        let remoteConfig = try await service.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(processor.processedRequests, [Request.remoteConfig(userId: userId, contextKey: "main")])
        XCTAssertEqual(remoteConfig.source.identifier, "rc_main")
        XCTAssertEqual(remoteConfig.source.contextKey, "main")
        XCTAssertEqual(remoteConfig.payload?["key"] as? String, "value")
    }

    func testLoadRemoteConfigSendsRemoteConfigRequestWithNilContextKey() async throws {
        let processor = MockRequestProcessor()
        processor.results = [makeRemoteConfig()]
        let service = makeService(processor: processor)

        _ = try await service.loadRemoteConfig(contextKey: nil)

        XCTAssertEqual(processor.processedRequests, [Request.remoteConfig(userId: userId, contextKey: nil)])
    }

    func testLoadRemoteConfigWrapsErrorIntoLoadingRemoteConfigFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.loadingRemoteConfigFailed) {
            _ = try await service.loadRemoteConfig(contextKey: "main")
        }
    }

    // MARK: - loadRemoteConfigList (all)

    func testLoadRemoteConfigListSendsAllRemoteConfigListRequest() async throws {
        let processor = MockRequestProcessor()
        processor.results = [[makeRemoteConfig(identifier: "rc_1"), makeRemoteConfig(identifier: "rc_2", contextKey: "extra")]]
        let service = makeService(processor: processor)

        let list = try await service.loadRemoteConfigList()

        XCTAssertEqual(processor.processedRequests, [Request.allRemoteConfigList(userId: userId)])
        XCTAssertEqual(list.remoteConfigs.count, 2)
        XCTAssertEqual(list.remoteConfigs[0].source.identifier, "rc_1")
        XCTAssertEqual(list.remoteConfigs[1].source.identifier, "rc_2")
    }

    func testLoadRemoteConfigListWrapsErrorIntoLoadingRemoteConfigListFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.loadingRemoteConfigListFailed) {
            _ = try await service.loadRemoteConfigList()
        }
    }

    // MARK: - loadRemoteConfigList (context keys)

    func testLoadRemoteConfigListWithContextKeysSendsRemoteConfigListRequest() async throws {
        let processor = MockRequestProcessor()
        processor.results = [[makeRemoteConfig(identifier: "rc_a", contextKey: "a")]]
        let service = makeService(processor: processor)

        let list = try await service.loadRemoteConfigList(contextKeys: ["a", "b"], includeEmptyContextKey: true)

        XCTAssertEqual(
            processor.processedRequests,
            [Request.remoteConfigList(userId: userId, contextKeys: ["a", "b"], includeEmptyContextKey: true)]
        )
        XCTAssertEqual(list.remoteConfigs.count, 1)
        XCTAssertEqual(list.remoteConfigs[0].source.contextKey, "a")
    }

    func testLoadRemoteConfigListWithContextKeysWrapsErrorIntoLoadingRemoteConfigListFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.loadingRemoteConfigListFailed) {
            _ = try await service.loadRemoteConfigList(contextKeys: ["a"], includeEmptyContextKey: false)
        }
    }

    // MARK: - attach/detach remote config

    func testAttachUserToRemoteConfigSendsAttachRequest() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor: processor)

        try await service.attachUserToRemoteConfig(id: "rc_id_1")

        XCTAssertEqual(
            processor.processedRequests,
            [Request.attachUserToRemoteConfig(userId: userId, remoteConfigId: "rc_id_1")]
        )
    }

    func testAttachUserToRemoteConfigWrapsErrorIntoAttachingUserToRemoteConfigFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.attachingUserToRemoteConfigFailed) {
            try await service.attachUserToRemoteConfig(id: "rc_id_1")
        }
    }

    func testDetachUserFromRemoteConfigSendsDetachRequest() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor: processor)

        try await service.detachUserFromRemoteConfig(id: "rc_id_2")

        XCTAssertEqual(
            processor.processedRequests,
            [Request.detachUserFromRemoteConfig(userId: userId, remoteConfigId: "rc_id_2")]
        )
    }

    func testDetachUserFromRemoteConfigWrapsErrorIntoDetachingUserFromRemoteConfigFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.detachingUserFromRemoteConfigFailed) {
            try await service.detachUserFromRemoteConfig(id: "rc_id_2")
        }
    }

    // MARK: - attach/detach experiment

    func testAttachUserToExperimentSendsAttachRequest() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor: processor)

        try await service.attachUserToExperiment(id: "exp_1", groupId: "group_1")

        XCTAssertEqual(
            processor.processedRequests,
            [Request.attachUserToExperiment(userId: userId, experimentId: "exp_1", groupId: "group_1")]
        )
    }

    func testAttachUserToExperimentWrapsErrorIntoAttachingUserToExperimentFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.attachingUserToExperimentFailed) {
            try await service.attachUserToExperiment(id: "exp_1", groupId: "group_1")
        }
    }

    func testDetachUserFromExperimentSendsDetachRequest() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor: processor)

        try await service.detachUserFromExperiment(id: "exp_2")

        XCTAssertEqual(
            processor.processedRequests,
            [Request.detachUserFromExperiment(userId: userId, experimentId: "exp_2")]
        )
    }

    func testDetachUserFromExperimentWrapsErrorIntoDetachingUserFromExperimentFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.detachingUserFromExperimentFailed) {
            try await service.detachUserFromExperiment(id: "exp_2")
        }
    }
}
