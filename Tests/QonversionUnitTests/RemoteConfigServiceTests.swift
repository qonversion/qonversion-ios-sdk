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

    private func makeService(processor: RequestProcessorInterface) -> RemoteConfigService {
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

    /// The REAL processor over a stubbed transport. The lossy decoding and the
    /// backend error classification both live on the wire path, so a mock that
    /// hands back ready objects cannot prove either.
    private func makeLiveService(json: String, status: Int = 200) -> RemoteConfigService {
        let networkProvider = MockNetworkProvider()
        networkProvider.responseData = Data(json.utf8)
        networkProvider.response = HTTPURLResponse(
            url: URL(string: "https://api2.qonversion.io/v4/remote-configs")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .qonversionTolerant
        let responseDecoder = ResponseDecoder(decoder: jsonDecoder)
        let criticalCodes: [ResponseCode] = [.unauthorized, .paymentRequired, .forbidden]
        let errorHandler = NetworkErrorHandler(criticalErrorCodes: criticalCodes, decoder: responseDecoder)
        let processor = RequestProcessor(
            baseURL: "https://api2.qonversion.io/",
            networkProvider: networkProvider,
            headersBuilder: MockHeadersBuilder(),
            errorHandler: errorHandler,
            decoder: responseDecoder,
            retriableRequestKinds: [],
            requestsStorage: MockRequestsStorage(),
            rateLimiter: MockRateLimiter()
        )
        return makeService(processor: processor)
    }

    private func remoteConfigRow(identifier: String, contextKey: String) -> String {
        return """
        {"payload": {"k": "v"}, "experiment": null, "source": {"uid": "\(identifier)", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": "\(contextKey)"}}
        """
    }

    // MARK: - lossy list decoding on the wire path

    func testOneMalformedRowDoesNotKillTheWholeList() async throws {
        let json = "[\(remoteConfigRow(identifier: "good", contextKey: "a")), {\"source\": {}}, \(remoteConfigRow(identifier: "also-good", contextKey: "b"))]"
        let service = makeLiveService(json: json)

        let list = try await service.loadRemoteConfigList()

        XCTAssertEqual(list.remoteConfigs.map { $0.source?.identifier }, ["good", "also-good"],
                       "a single bad row must degrade the list, not null it")
    }

    func testOneMalformedRowDoesNotKillTheContextKeyedList() async throws {
        let json = "[{\"source\": {}}, \(remoteConfigRow(identifier: "good", contextKey: "a"))]"
        let service = makeLiveService(json: json)

        let list = try await service.loadRemoteConfigList(contextKeys: ["a"], includeEmptyContextKey: false)

        XCTAssertEqual(list.remoteConfigs.map { $0.source?.identifier }, ["good"])
    }

    func testAnAllMalformedListStillFails() async {
        // A schema break must not be laundered into an empty list — the caller
        // would persist it over its offline data.
        let service = makeLiveService(json: #"[{"source": {}}, {"source": {}}]"#)

        do {
            _ = try await service.loadRemoteConfigList()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertNotEqual(error.type, .unknown)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    // MARK: - error granularity

    func testANotFoundOnTheConfigEndpointBecomesRemoteConfigurationNotAvailable() async {
        // The ObjC SDK had QONErrorCodeRemoteConfigurationNotAvailable for
        // exactly this: the user (or context key) has no configuration.
        let service = makeLiveService(
            json: #"{"error": {"type": "resource", "code": "relation_not_found", "message": "no config"}}"#,
            status: 404
        )

        do {
            _ = try await service.loadRemoteConfig(contextKey: "main")
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .remoteConfigurationNotAvailable)
            XCTAssertEqual(error.apiCode, "relation_not_found", "the backend code must survive the RC layer")
            XCTAssertEqual(error.apiType, "resource")
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testANotFoundOnTheListEndpointBecomesRemoteConfigurationNotAvailable() async {
        let service = makeLiveService(
            json: #"{"error": {"type": "resource", "code": "not_found", "message": "no configs"}}"#,
            status: 404
        )

        do {
            _ = try await service.loadRemoteConfigList()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .remoteConfigurationNotAvailable)
            XCTAssertEqual(error.apiCode, "not_found")
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testAnUnknownUserIsNotDisguisedAsAMissingConfiguration() async {
        // `user_not_found` also classifies as .resourceNotFound, but it means
        // the SDK asked about a user the backend does not have — a real error,
        // not "this user has no config", and the integrator must be able to
        // tell them apart.
        let service = makeLiveService(
            json: #"{"error": {"type": "resource", "code": "user_not_found", "message": "no such user"}}"#,
            status: 404
        )

        do {
            _ = try await service.loadRemoteConfig(contextKey: "main")
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .resourceNotFound)
            XCTAssertEqual(error.apiCode, "user_not_found")
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testANotFoundOnAttachIsNotAMissingConfiguration() async {
        // On attach/detach a 404 means the id the CALLER passed is unknown.
        let service = makeLiveService(
            json: #"{"error": {"type": "resource", "code": "not_found", "message": "no such remote configuration"}}"#,
            status: 404
        )

        do {
            try await service.attachUserToRemoteConfig(id: "rc_missing")
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .resourceNotFound, "the id the caller passed does not exist")
            XCTAssertEqual(error.apiCode, "not_found")
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testANotFoundOnExperimentDetachIsNotAMissingConfiguration() async {
        let service = makeLiveService(
            json: #"{"error": {"type": "resource", "code": "relation_not_found", "message": "no such experiment"}}"#,
            status: 404
        )

        do {
            try await service.detachUserFromExperiment(id: "exp_missing")
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .resourceNotFound)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testAClassifiedBackendErrorKeepsItsTypeAndApiFields() async {
        // Rewrapping every failure into .loadingRemoteConfigFailed erased both
        // the classification and the backend code the integrator branches on.
        let service = makeLiveService(
            json: #"{"error": {"type": "request", "code": "too_many_requests", "message": "slow down"}}"#,
            status: 429
        )

        do {
            _ = try await service.loadRemoteConfig(contextKey: nil)
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .rateLimitExceeded)
            XCTAssertEqual(error.apiCode, "too_many_requests")
            XCTAssertEqual(error.apiType, "request")
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testACriticalErrorIsNotDisguisedAsAConfigFailure() async {
        let service = makeLiveService(
            json: #"{"error": {"type": "request", "code": "control_unauthorized", "message": "revoked"}}"#,
            status: 401
        )

        do {
            _ = try await service.loadRemoteConfigList()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .critical, "a revoked project key must stay critical")
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testAnUnclassifiableFailureStillBecomesLoadingRemoteConfigFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        await assertThrows(.loadingRemoteConfigFailed) {
            _ = try await service.loadRemoteConfig(contextKey: "main")
        }
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
        XCTAssertEqual(remoteConfig.source?.identifier, "rc_main")
        XCTAssertEqual(remoteConfig.source?.contextKey, "main")
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
        let configs: [Qonversion.RemoteConfig] = [makeRemoteConfig(identifier: "rc_1"), makeRemoteConfig(identifier: "rc_2", contextKey: "extra")]
        processor.results = [Qonversion.RemoteConfigList(remoteConfigs: configs)]
        let service = makeService(processor: processor)

        let list = try await service.loadRemoteConfigList()

        XCTAssertEqual(processor.processedRequests, [Request.allRemoteConfigList(userId: userId)])
        XCTAssertEqual(list.remoteConfigs.count, 2)
        XCTAssertEqual(list.remoteConfigs[0].source?.identifier, "rc_1")
        XCTAssertEqual(list.remoteConfigs[1].source?.identifier, "rc_2")
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
        let configs: [Qonversion.RemoteConfig] = [makeRemoteConfig(identifier: "rc_a", contextKey: "a")]
        processor.results = [Qonversion.RemoteConfigList(remoteConfigs: configs)]
        let service = makeService(processor: processor)

        let list = try await service.loadRemoteConfigList(contextKeys: ["a", "b"], includeEmptyContextKey: true)

        XCTAssertEqual(
            processor.processedRequests,
            [Request.remoteConfigList(userId: userId, contextKeys: ["a", "b"], includeEmptyContextKey: true)]
        )
        XCTAssertEqual(list.remoteConfigs.count, 1)
        XCTAssertEqual(list.remoteConfigs[0].source?.contextKey, "a")
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
