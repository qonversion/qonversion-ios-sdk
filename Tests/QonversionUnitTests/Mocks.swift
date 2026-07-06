//
//  Mocks.swift
//  QonversionUnitTests
//
//  Shared mocks for all unit tests. One mock per SDK interface.
//  Keep this the single place where interface conformances live —
//  test files must not redeclare mocks.
//

import Foundation
import StoreKit
@testable import Qonversion

enum MockError: Error, Equatable {
    case noStub
    case typeMismatch
    case stubbed
}

// MARK: - Test UserDefaults

enum TestDefaults {
    /// Creates an isolated, pre-cleaned UserDefaults suite for a test.
    static func makeIsolated(_ name: String = #function) -> UserDefaults {
        let suiteName = "io.qonversion.tests." + name + "." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

// MARK: - NetworkLayer

final class MockRequestProcessor: RequestProcessorInterface {

    /// Stubbed results returned in order. Put decoded values of the expected response type here.
    var results: [Any] = []
    var error: Error?
    private(set) var processedRequests: [Request] = []

    func process<T>(request: Request, responseType: T.Type) async throws -> T where T: Decodable {
        processedRequests.append(request)
        if let error { throw error }
        guard !results.isEmpty else { throw MockError.noStub }
        let next = results.removeFirst()
        guard let typed = next as? T else { throw MockError.typeMismatch }
        return typed
    }
}

final class MockNetworkProvider: NetworkProviderInterface {

    var responseData: Data = Data()
    var response: URLResponse = HTTPURLResponse(url: URL(string: "https://api.qonversion.io")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    var error: Error?
    private(set) var sentRequests: [URLRequest] = []

    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        sentRequests.append(request)
        if let error { throw error }
        return (responseData, response)
    }
}

final class MockHeadersBuilder: HeadersBuilderInterface {

    private(set) var callsCount = 0

    func addHeaders(to request: inout URLRequest) {
        callsCount += 1
        request.setValue("test", forHTTPHeaderField: "X-Test-Header")
    }
}

final class MockNetworkErrorHandler: NetworkErrorHandlerInterface {

    var errorToReturn: QonversionError?
    private(set) var callsCount = 0

    func extractError(from response: URLResponse, body: Data) -> QonversionError? {
        callsCount += 1
        return errorToReturn
    }
}

final class MockResponseDecoder: ResponseDecoderInterface {

    /// When set, returned instead of real decoding (must match T).
    var stub: Any?
    var error: Error?
    private let realDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
        if let error { throw error }
        if let stub {
            guard let typed = stub as? T else { throw MockError.typeMismatch }
            return typed
        }
        return try realDecoder.decode(type, from: data)
    }
}

final class MockRateLimiter: RateLimiterInterface {

    var errorToReturn: QonversionError?
    private(set) var validatedRequests: [Request] = []

    func validateRateLimit(for request: Request) -> QonversionError? {
        validatedRequests.append(request)
        return errorToReturn
    }
}

final class MockRequestsStorage: RequestsStorageInterface {

    private(set) var storedRequests: [URLRequest] = []
    private(set) var cleanCallsCount = 0

    func store(requests: [URLRequest]) {
        storedRequests = requests
    }

    func append(requests: [URLRequest]) {
        storedRequests.append(contentsOf: requests)
    }

    func fetchRequests() -> [URLRequest] {
        return storedRequests
    }

    func clean() {
        cleanCallsCount += 1
        storedRequests = []
    }
}

// MARK: - Storage

/// In-memory LocalStorageInterface. Typed set/object mirror the real
/// LocalStorage (JSON round-trip). Prefer the REAL LocalStorage over
/// TestDefaults.makeIsolated() when the storage behavior itself matters.
final class MockLocalStorage: LocalStorageInterface {

    private(set) var storage: [String: Any] = [:]
    var setError: Error?
    var objectError: Error?

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    func object<T>(forKey key: String, dataType: T.Type) throws -> T? where T: Decodable {
        if let objectError { throw objectError }
        guard let data = storage[key] as? Data else { return nil }
        return try jsonDecoder.decode(dataType, from: data)
    }

    func set(_ value: Encodable?, forKey key: String) throws {
        if let setError { throw setError }
        guard let value else {
            storage.removeValue(forKey: key)
            return
        }
        storage[key] = try jsonEncoder.encode(value)
    }

    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
    func string(forKey key: String) -> String? { storage[key] as? String }
    func array(forKey key: String) -> [Any]? { storage[key] as? [Any] }
    func dictionary(forKey key: String) -> [String: Any]? { storage[key] as? [String: Any] }
    func data(forKey key: String) -> Data? { storage[key] as? Data }
    func integer(forKey key: String) -> Int { storage[key] as? Int ?? 0 }
    func float(forKey key: String) -> Float { storage[key] as? Float ?? 0 }
    func double(forKey key: String) -> Double { storage[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { storage[key] as? Bool ?? false }
    func url(forKey key: String) -> URL? { storage[key] as? URL }
    func set(string: String, forKey key: String) { storage[key] = string }
    func set(integer: Int, forKey key: String) { storage[key] = integer }
    func set(float: Float, forKey key: String) { storage[key] = float }
    func set(double: Double, forKey key: String) { storage[key] = double }
    func set(bool: Bool, forKey key: String) { storage[key] = bool }
}

// MARK: - StoreKit

final class MockStoreKitFacade: StoreKitFacadeInterface {

    var productsResult: [StoreProductWrapper] = []
    var productsError: Error?
    private(set) var requestedProductIds: [[String]] = []

    var restoreResult: [Qonversion.Transaction] = []
    var restoreError: Error?

    func products(for ids: [String]) async throws -> [StoreProductWrapper] {
        requestedProductIds.append(ids)
        if let productsError { throw productsError }
        return productsResult
    }

    func currentEntitlements() async -> [Qonversion.Transaction] { [] }

    func restore() async throws -> [Qonversion.Transaction] {
        if let restoreError { throw restoreError }
        return restoreResult
    }

    func finish(transaction: SKPaymentTransaction) {}

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func finish(transaction: StoreKit.Transaction) async {}

    func subscribe() async -> [Qonversion.Transaction] { [] }

    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {}

    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {}
    #endif
}

// MARK: - Services

final class MockProductsService: ProductsServiceInterface {

    var productsResult: [Qonversion.Product] = []
    var error: Error?
    private(set) var productsCallsCount = 0

    func products() async throws -> [Qonversion.Product] {
        productsCallsCount += 1
        if let error { throw error }
        return productsResult
    }
}

final class MockRemoteConfigService: RemoteConfigServiceInterface {

    var remoteConfigResult: Qonversion.RemoteConfig?
    var remoteConfigListResult: Qonversion.RemoteConfigList?
    var error: Error?

    private(set) var loadRemoteConfigContextKeys: [String?] = []
    private(set) var loadListCallsCount = 0
    private(set) var loadListContextKeysArgs: [(contextKeys: [String], includeEmpty: Bool)] = []
    private(set) var attachedRemoteConfigIds: [String] = []
    private(set) var detachedRemoteConfigIds: [String] = []
    private(set) var attachedExperiments: [(id: String, groupId: String)] = []
    private(set) var detachedExperimentIds: [String] = []

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig {
        loadRemoteConfigContextKeys.append(contextKey)
        if let error { throw error }
        guard let remoteConfigResult else { throw MockError.noStub }
        return remoteConfigResult
    }

    func loadRemoteConfigList() async throws -> Qonversion.RemoteConfigList {
        loadListCallsCount += 1
        if let error { throw error }
        guard let remoteConfigListResult else { throw MockError.noStub }
        return remoteConfigListResult
    }

    func loadRemoteConfigList(contextKeys: [String], includeEmptyContextKey: Bool) async throws -> Qonversion.RemoteConfigList {
        loadListContextKeysArgs.append((contextKeys, includeEmptyContextKey))
        if let error { throw error }
        guard let remoteConfigListResult else { throw MockError.noStub }
        return remoteConfigListResult
    }

    func attachUserToRemoteConfig(id: String) async throws {
        attachedRemoteConfigIds.append(id)
        if let error { throw error }
    }

    func detachUserFromRemoteConfig(id: String) async throws {
        detachedRemoteConfigIds.append(id)
        if let error { throw error }
    }

    func attachUserToExperiment(id: String, groupId: String) async throws {
        attachedExperiments.append((id, groupId))
        if let error { throw error }
    }

    func detachUserFromExperiment(id: String) async throws {
        detachedExperimentIds.append(id)
        if let error { throw error }
    }
}

final class MockUserService: UserServiceInterface {

    var userResult: Qonversion.User?
    var createUserResult: Qonversion.User?
    var error: Error?
    var generatedUserId = "QON_test_generated"

    private(set) var userCallsCount = 0
    private(set) var createUserCallsCount = 0

    func user() async throws -> Qonversion.User {
        userCallsCount += 1
        if let error { throw error }
        guard let userResult else { throw MockError.noStub }
        return userResult
    }

    func createUser() async throws -> Qonversion.User {
        createUserCallsCount += 1
        if let error { throw error }
        guard let createUserResult else { throw MockError.noStub }
        return createUserResult
    }

    func generateUserId() -> String {
        return generatedUserId
    }
}

// MARK: - Device

final class MockDeviceInfoCollector: DeviceInfoCollectorInterface {

    var device = Device(
        manufacturer: "Apple",
        osName: "iOS",
        osVersion: "17.0",
        model: "iPhone15,2",
        appVersion: "1.2.3",
        country: "US",
        language: "en",
        timezone: "America/New_York",
        advertisingId: nil,
        vendorId: "vendor-id",
        installDate: 1_700_000_000
    )
    var advertisingIdValue: String?

    func deviceInfo() -> Device { device }
    func advertisingId() -> String? { advertisingIdValue }
}

final class MockDeviceService: DeviceServiceInterface {

    var current: Device?
    var createResult: Device?
    var updateResult: Device?
    var error: Error?
    var saveError: Error?
    var currentDeviceError: Error?

    private(set) var savedDevices: [Device] = []
    private(set) var createdDevices: [Device] = []
    private(set) var updatedDevices: [Device] = []

    func save(device: Device) throws {
        if let saveError { throw saveError }
        savedDevices.append(device)
    }

    func currentDevice() throws -> Device? {
        if let currentDeviceError { throw currentDeviceError }
        return current
    }

    func create(device: Device) async throws -> Device {
        createdDevices.append(device)
        if let error { throw error }
        return createResult ?? device
    }

    func update(device: Device) async throws -> Device {
        updatedDevices.append(device)
        if let error { throw error }
        return updateResult ?? device
    }
}
