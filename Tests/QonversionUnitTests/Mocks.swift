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
    var onProcess: (() async -> Void)?
    private(set) var processedRequests: [Request] = []
    private(set) var processedTriggers: [RequestTrigger?] = []

    func process<T>(request: Request, responseType: T.Type, trigger: RequestTrigger?) async throws -> T where T: Decodable {
        processedRequests.append(request)
        processedTriggers.append(trigger)
        await onProcess?()
        if let error { throw error }
        guard !results.isEmpty else { throw MockError.noStub }
        let next = results.removeFirst()
        guard let typed = next as? T else { throw MockError.typeMismatch }
        return typed
    }

    private(set) var processStoredRequestsCallsCount = 0
    func processStoredRequests() {
        processStoredRequestsCallsCount += 1
    }
}

final class MockNetworkProvider: NetworkProviderInterface {

    var responseData: Data = Data()
    var response: URLResponse = HTTPURLResponse(url: URL(string: "https://api.qonversion.io")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    var error: Error?
    var onSend: (() async -> Void)?
    private let providerStateLock = NSLock()
    private var _sentRequests: [URLRequest] = []
    var sentRequests: [URLRequest] {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return _sentRequests
    }

    private func record(_ request: URLRequest) {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        _sentRequests.append(request)
    }

    /// Errors handed out one per send, before `error`: lets a test make the
    /// transport fail and then recover.
    var errorSequence: [Error?] = []

    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        record(request)
        await onSend?()

        providerStateLock.lock()
        var scripted: Error?? = Error??.none
        if !errorSequence.isEmpty {
            scripted = Error??.some(errorSequence.removeFirst())
        }
        providerStateLock.unlock()

        if let scriptedOutcome: Error? = scripted {
            if let scriptedError: Error = scriptedOutcome { throw scriptedError }

            return (responseData, response)
        }

        if let error { throw error }
        return (responseData, response)
    }
}

final class MockIntegrationsInfoCollector: IntegrationsInfoCollectorInterface {

    var adjustUserIdResult: String?
    var appsFlyerUserIdResult: String?
    var facebookAnonymousIdResult: String?

    func adjustUserId(completion: @escaping @Sendable (String?) -> Void) {
        completion(adjustUserIdResult)
    }

    func appsFlyerUserId() -> String? { appsFlyerUserIdResult }

    func facebookAnonymousId() -> String? { facebookAnonymousIdResult }
}


final class MockUserPropertiesManager: UserPropertiesManagerInterface {

    var userPropertiesResult: Qonversion.UserProperties?
    var error: Error?
    private(set) var sendPropertiesCallsCount = 0
    private(set) var sendPropertiesForceFlags: [Bool] = []
    var onSendProperties: (() async -> Void)?

    func userProperties() async throws -> Qonversion.UserProperties {
        if let error { throw error }
        guard let userPropertiesResult else { throw MockError.noStub }
        return userPropertiesResult
    }

    func setUserProperty(key: Qonversion.UserPropertyKey, value: String) { }

    func setCustomUserProperty(key: String, value: String) { }

    func sendProperties(force: Bool) async throws {
        sendPropertiesCallsCount += 1
        sendPropertiesForceFlags.append(force)
        await onSendProperties?()
        if let error { throw error }
    }

    func clearDelayedProperties() { }

    func collectAppleSearchAdsAttribution() { }

    private(set) var collectIntegrationsDataCallsCount = 0

    func collectIntegrationsData() {
        collectIntegrationsDataCallsCount += 1
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

    private(set) var storedRequests: [StoredRequest] = []
    private(set) var cleanCallsCount = 0
    private(set) var cleanGeneration = 0

    func append(_ request: StoredRequest, ifGenerationIs generation: Int) {
        guard cleanGeneration == generation else { return }
        if let dedupKey = request.dedupKey, storedRequests.contains(where: { $0.dedupKey == dedupKey }) {
            return
        }
        storedRequests.append(request)
    }

    func remove(_ request: StoredRequest) {
        if let index = storedRequests.firstIndex(of: request) {
            storedRequests.remove(at: index)
        }
    }

    func replace(_ request: StoredRequest, with replacement: StoredRequest, ifGenerationIs generation: Int) {
        guard cleanGeneration == generation, let index = storedRequests.firstIndex(of: request) else { return }

        storedRequests[index] = replacement
    }

    func removeAll(ifGenerationIs generation: Int, where shouldRemove: @Sendable (StoredRequest) -> Bool) {
        guard cleanGeneration == generation else { return }

        storedRequests.removeAll(where: shouldRemove)
    }

    func fetchRequests() -> [StoredRequest] {
        return storedRequests
    }

    func clean() {
        cleanCallsCount += 1
        cleanGeneration += 1
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

    var currentEntitlementsResult: [Qonversion.Transaction] = []
    var restoreResult: [Qonversion.Transaction] = []
    var restoreError: Error?
    var historicalDataResult: [Qonversion.Transaction] = []
    var unfinishedTransactionsResult: [Qonversion.Transaction] = []
    private(set) var unfinishedTransactionsCallsCount = 0
    var purchaseResult: Qonversion.Transaction?
    var purchaseError: Error?
    private(set) var purchasedStoreIds: [String] = []
    private(set) var purchasedOptions: [Qonversion.PurchaseOptions] = []
    private let facadeStateLock = NSLock()
    private var _finishedTransactions: [Qonversion.Transaction] = []
    var finishedTransactions: [Qonversion.Transaction] {
        facadeStateLock.lock()
        defer { facadeStateLock.unlock() }
        return _finishedTransactions
    }
    private(set) var startObservingCallsCount = 0
    private(set) var stopObservingCallsCount = 0

    var onPurchase: (() async -> Void)?

    func purchase(storeId: String, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction {
        purchasedStoreIds.append(storeId)
        purchasedOptions.append(options)
        await onPurchase?()
        if let purchaseError { throw purchaseError }
        guard let purchaseResult else { throw MockError.noStub }
        return purchaseResult
    }

    func products(for ids: [String]) async throws -> [StoreProductWrapper] {
        requestedProductIds.append(ids)
        if let productsError { throw productsError }
        return productsResult
    }

    var introOfferEligibilityResults: [String: Bool] = [:]
    private var _eligibilityRequestedStoreIds: [String] = []
    /// Recorded under the lock: the SDK asks about the products concurrently.
    var eligibilityRequestedStoreIds: [String] {
        facadeStateLock.lock()
        defer { facadeStateLock.unlock() }
        return _eligibilityRequestedStoreIds
    }

    func isEligibleForIntroOffer(storeId: String) async -> Bool? {
        facadeStateLock.lock()
        _eligibilityRequestedStoreIds.append(storeId)
        facadeStateLock.unlock()

        return introOfferEligibilityResults[storeId]
    }

    func currentEntitlements() async -> [Qonversion.Transaction] { currentEntitlementsResult }

    private var _storefrontContinuation: AsyncStream<Void>.Continuation?

    /// True once the SDK's observation task has actually subscribed — the
    /// subscription happens on another task, so tests wait for it instead of
    /// sleeping.
    var hasStorefrontSubscriber: Bool {
        facadeStateLock.lock()
        defer { facadeStateLock.unlock() }
        return _storefrontContinuation != nil
    }

    func emitStorefrontChange() {
        facadeStateLock.lock()
        let continuation = _storefrontContinuation
        facadeStateLock.unlock()
        continuation?.yield(())
    }

    func storefrontUpdates() -> AsyncStream<Void> {
        return AsyncStream { continuation in
            self.facadeStateLock.lock()
            self._storefrontContinuation = continuation
            self.facadeStateLock.unlock()
        }
    }

    private(set) var facadeRestoreCallsCount = 0
    var onRestore: (() async -> Void)?

    func restore() async throws -> [Qonversion.Transaction] {
        facadeRestoreCallsCount += 1
        await onRestore?()
        if let restoreError { throw restoreError }
        return restoreResult
    }

    func historicalData() async throws -> [Qonversion.Transaction] { historicalDataResult }

    func unfinishedTransactions() async -> [Qonversion.Transaction] {
        unfinishedTransactionsCallsCount += 1
        return unfinishedTransactionsResult
    }

    func map(_ verificationResult: VerificationResult<StoreKit.Transaction>) -> Qonversion.Transaction? {
        guard case .verified(let transaction) = verificationResult else { return nil }
        return StoreKitMapper().map(transaction, jws: verificationResult.jwsRepresentation)
    }

    func finish(_ transaction: Qonversion.Transaction) async {
        facadeStateLock.lock()
        _finishedTransactions.append(transaction)
        facadeStateLock.unlock()
    }

    func startObservingTransactionUpdates() {
        startObservingCallsCount += 1
    }

    func stopObservingTransactionUpdates() {
        stopObservingCallsCount += 1
    }

    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {}

    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {}
    #endif
}

/// Mock of the StoreKit 2 wrapper — domain-typed, so the facade logic is fully
/// unit-testable without real StoreKit objects. The updates stream is driven
/// by the test through `emitUpdate`/`finishUpdates`.
final class MockStoreKit2Wrapper: StoreKitWrapperInterface {

    weak var delegate: StoreKitWrapperDelegate?

    // The SDK's detached tasks mutate this mock while the test thread polls
    // it — the hot members are lock-guarded.
    private let stateLock = NSLock()
    var currentEntitlementsResult: [Qonversion.Transaction] = []
    var restoreResult: [Qonversion.Transaction] = []
    var restoreError: Error?
    var fetchAllResult: [Qonversion.Transaction] = []
    var fetchUnfinishedResult: [Qonversion.Transaction] = []

    private var _finishedTransactions: [Qonversion.Transaction] = []
    var finishedTransactions: [Qonversion.Transaction] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _finishedTransactions
    }
    private(set) var restoreCallsCount = 0
    private var _transactionUpdatesCallsCount = 0
    // The facade subscribes to the transaction and storefront streams from two
    // concurrent tasks — every shared field here is lock-guarded.
    var transactionUpdatesCallsCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _transactionUpdatesCallsCount
    }

    private var _updatesContinuation: AsyncStream<Qonversion.Transaction>.Continuation?
    private var _storefrontContinuation: AsyncStream<Void>.Continuation?

    func emitUpdate(_ transaction: Qonversion.Transaction) {
        stateLock.lock()
        let continuation = _updatesContinuation
        stateLock.unlock()
        continuation?.yield(transaction)
    }

    func emitStorefrontChange() {
        stateLock.lock()
        let continuation = _storefrontContinuation
        stateLock.unlock()
        continuation?.yield(())
    }

    func storefrontUpdates() -> AsyncStream<Void> {
        return AsyncStream { continuation in
            self.stateLock.lock()
            self._storefrontContinuation = continuation
            self.stateLock.unlock()
        }
    }

    func finishUpdates() {
        stateLock.lock()
        let continuation = _updatesContinuation
        stateLock.unlock()
        continuation?.finish()
    }

    func purchase(product: StoreKit.Product, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction {
        throw MockError.noStub
    }

    var productsError: Error?

    func products(for ids: [String]) async throws -> [StoreKit.Product] {
        if let productsError { throw productsError }
        return []
    }

    func currentEntitlements() async -> [Qonversion.Transaction] { currentEntitlementsResult }

    func restore() async throws -> [Qonversion.Transaction] {
        restoreCallsCount += 1
        if let restoreError { throw restoreError }
        return restoreResult
    }

    func fetchAll() async -> [Qonversion.Transaction] { fetchAllResult }

    func fetchUnfinished() async -> [Qonversion.Transaction] { fetchUnfinishedResult }

    private(set) var subscribeToPromoPurchasesCallsCount = 0
    func unsubscribeFromPromoPurchases() { }

    func subscribeToPromoPurchases() {
        subscribeToPromoPurchasesCallsCount += 1
    }

    func finish(_ transaction: Qonversion.Transaction) async {
        stateLock.lock()
        _finishedTransactions.append(transaction)
        stateLock.unlock()
    }

    func transactionUpdates() -> AsyncStream<Qonversion.Transaction> {
        return AsyncStream { continuation in
            self.stateLock.lock()
            self._updatesContinuation = continuation
            self._transactionUpdatesCallsCount += 1
            self.stateLock.unlock()
        }
    }

    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, visionOS 1.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {}
    #endif
}

/// Mock of the legacy StoreKit 1 wrapper. Captures completions so tests can
/// fire them at a controlled moment (e.g. after the facade is deallocated).

// MARK: - Services

final class MockProductsService: ProductsServiceInterface {

    var productsResult: [Qonversion.Product] = []
    var error: Error?
    var productPermissionsResult: [String: [String]] = [:]
    var productPermissionsError: Error?
    private(set) var productsCallsCount = 0
    private(set) var productPermissionsCallsCount = 0

    var onProducts: (() async -> Void)?

    func products() async throws -> [Qonversion.Product] {
        productsCallsCount += 1
        await onProducts?()
        if let error { throw error }
        return productsResult
    }

    func productPermissions() async throws -> [String: [String]] {
        productPermissionsCallsCount += 1
        if let productPermissionsError { throw productPermissionsError }
        return productPermissionsResult
    }
}

final class MockRemoteConfigService: RemoteConfigServiceInterface {

    var remoteConfigResult: Qonversion.RemoteConfig?
    var remoteConfigListResult: Qonversion.RemoteConfigList?
    var error: Error?

    // Concurrent callers share one request, so the recording is lock-guarded.
    private let serviceStateLock = NSLock()
    private var _loadRemoteConfigContextKeys: [String?] = []
    var loadRemoteConfigContextKeys: [String?] {
        serviceStateLock.lock()
        defer { serviceStateLock.unlock() }
        return _loadRemoteConfigContextKeys
    }
    private(set) var loadListCallsCount = 0
    private(set) var loadListContextKeysArgs: [(contextKeys: [String], includeEmpty: Bool)] = []
    private(set) var attachedRemoteConfigIds: [String] = []
    private(set) var detachedRemoteConfigIds: [String] = []
    private(set) var attachedExperiments: [(id: String, groupId: String)] = []
    private(set) var detachedExperimentIds: [String] = []

    var onLoadRemoteConfig: (() async -> Void)?

    func loadRemoteConfig(contextKey: String?) async throws -> Qonversion.RemoteConfig {
        serviceStateLock.lock()
        _loadRemoteConfigContextKeys.append(contextKey)
        serviceStateLock.unlock()
        await onLoadRemoteConfig?()
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
    /// Fails user() only, leaving the creation gate healthy.
    var userError: Error?
    var generatedUserId = "QON_test_generated"

    // Identity stubs
    /// Linked uid returned by identity(for:); nil models "not linked yet" (404).
    var identityLinkedUid: String?
    var identityError: Error?
    var createIdentityError: Error?
    /// Uid returned by createIdentity; defaults to the passed userId.
    var createIdentityResultUid: String?

    // Async hooks — let tests hold a call open to assert sequencing.
    var onCreateUser: (() async -> Void)?
    var onIdentity: (() async -> Void)?
    var onCreateIdentity: (() async -> Void)?

    private(set) var userCallsCount = 0
    private(set) var createUserCallsCount = 0
    private(set) var identityCalls: [String] = []
    private(set) var createIdentityCalls: [(externalId: String, userId: String)] = []
    /// Ordered log of every call: "createUser", "identity", "createIdentity", "user".
    private(set) var callLog: [String] = []

    func user() async throws -> Qonversion.User {
        userCallsCount += 1
        callLog.append("user")
        if let userError { throw userError }
        if let error { throw error }
        guard let userResult else { throw MockError.noStub }
        return userResult
    }

    func createUser() async throws -> Qonversion.User {
        createUserCallsCount += 1
        callLog.append("createUser")
        await onCreateUser?()
        if let error { throw error }
        guard let createUserResult else { throw MockError.noStub }
        return createUserResult
    }

    func generateUserId() -> String {
        return generatedUserId
    }

    func identity(for externalId: String) async throws -> String? {
        identityCalls.append(externalId)
        callLog.append("identity")
        await onIdentity?()
        if let identityError { throw identityError }
        return identityLinkedUid
    }

    func createIdentity(externalId: String, userId: String) async throws -> String {
        createIdentityCalls.append((externalId, userId))
        callLog.append("createIdentity")
        await onCreateIdentity?()
        if let createIdentityError { throw createIdentityError }
        return createIdentityResultUid ?? userId
    }
}

final class UserChangeObserverSpy: UserChangedObserver {
    private(set) var userDidChangeCallsCount = 0
    func userDidChange() { userDidChangeCallsCount += 1 }
}

final class MockUserManager: UserManagerInterface {

    var user: Qonversion.User?
    var error: Error?
    private(set) var obtainUserCallsCount = 0
    private(set) var identifyCalls: [String] = []
    private(set) var logoutCallsCount = 0
    private(set) var userInfoCallsCount = 0

    @discardableResult
    func obtainUser() async throws -> Qonversion.User {
        obtainUserCallsCount += 1
        if let error { throw error }
        guard let user else { throw MockError.noStub }
        return user
    }

    @discardableResult
    func identify(_ externalId: String) async throws -> Qonversion.User {
        identifyCalls.append(externalId)
        if let error { throw error }
        guard let user else { throw MockError.noStub }
        return user
    }

    func logout() async {
        logoutCallsCount += 1
    }

    private(set) var awaitUserStabilityCallsCount = 0
    var awaitUserStabilityError: Error?
    var onAwaitUserStability: (() async -> Void)?

    func awaitUserStability() async throws {
        awaitUserStabilityCallsCount += 1
        await onAwaitUserStability?()
        if let awaitUserStabilityError { throw awaitUserStabilityError }
    }

    private(set) var switchedToUserIds: [String] = []

    func switchToUser(with uid: String) async throws {
        switchedToUserIds.append(uid)
        if let error { throw error }
    }

    func userInfo() async throws -> Qonversion.User {
        userInfoCallsCount += 1
        if let error { throw error }
        guard let user else { throw MockError.noStub }
        return user
    }
}

final class MockFallbackService: FallbackServiceInterface {

    var fallbackData: FallbackData?
    private(set) var obtainCallsCount = 0

    func obtainFallbackData() -> FallbackData? {
        obtainCallsCount += 1
        return fallbackData
    }
}

final class MockPurchasesService: PurchasesServiceInterface {

    var error: Error?
    var onSend: (() async -> Void)?
    private let serviceStateLock = NSLock()
    private var _sentTransactions: [(transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?)] = []
    var sentTransactions: [(transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?)] {
        serviceStateLock.lock()
        defer { serviceStateLock.unlock() }
        return _sentTransactions
    }
    private var _sentTriggers: [RequestTrigger] = []
    var sentTriggers: [RequestTrigger] {
        serviceStateLock.lock()
        defer { serviceStateLock.unlock() }
        return _sentTriggers
    }

    var promotionalOfferResult: Qonversion.PromotionalOffer?
    private(set) var promotionalOfferCalls: [(userId: String, offerId: String, productStoreId: String)] = []

    var reportedOwnerUserId: String?

    @discardableResult
    func send(_ transaction: Qonversion.Transaction, userId: String, options: Qonversion.PurchaseOptions?, trigger: RequestTrigger) async throws -> String? {
        serviceStateLock.lock()
        _sentTransactions.append((transaction, userId, options))
        _sentTriggers.append(trigger)
        serviceStateLock.unlock()
        await onSend?()
        if let error { throw error }
        return reportedOwnerUserId
    }

    func promotionalOffer(userId: String, offerId: String, productStoreId: String) async throws -> Qonversion.PromotionalOffer {
        promotionalOfferCalls.append((userId, offerId, productStoreId))
        if let error { throw error }
        guard let promotionalOfferResult else { throw MockError.noStub }
        return promotionalOfferResult
    }
}

final class MockEntitlementsService: EntitlementsServiceInterface {

    var entitlementsResult: [Qonversion.Entitlement] = []
    var error: Error?
    var onEntitlements: (() async -> Void)?
    private(set) var entitlementsCalls: [String] = []

    func entitlements(userId: String) async throws -> [Qonversion.Entitlement] {
        entitlementsCalls.append(userId)
        await onEntitlements?()
        if let error { throw error }
        return entitlementsResult
    }
}

final class MockProductsManager: ProductsManagerInterface, ProductsDataSource {

    var productsResult: [Qonversion.Product] = []
    var productsError: Error?
    var cachedProductsResult: [Qonversion.Product] = []
    var cachedMapping: [String: [String]]?
    private(set) var loadPermissionsCallsCount = 0

    func products() async throws -> [Qonversion.Product] {
        if let productsError { throw productsError }
        return productsResult
    }

    func loadProductPermissions() async {
        loadPermissionsCallsCount += 1
    }

    private(set) var startObservingStorefrontChangesCallsCount = 0

    func startObservingStorefrontChanges() {
        startObservingStorefrontChangesCallsCount += 1
    }

    var fallbackFileAccessible = false

    func isFallbackFileAccessible() -> Bool { fallbackFileAccessible }

    var eligibilityResult: [String: Qonversion.IntroEligibilityStatus] = [:]
    private(set) var eligibilityRequestedProductIds: [[String]] = []

    func checkTrialIntroEligibility(productIds: [String]) async throws -> [String: Qonversion.IntroEligibilityStatus] {
        eligibilityRequestedProductIds.append(productIds)
        return eligibilityResult
    }

    func cachedProductPermissions() -> [String: [String]]? { cachedMapping }

    func cachedProducts() -> [Qonversion.Product] { cachedProductsResult }
}

final class MockEntitlementsManager: EntitlementsManagerInterface {

    var entitlementsResult: [String: Qonversion.Entitlement] = [:]
    var entitlementsError: Error?
    var localFallbackResult: [String: Qonversion.Entitlement] = [:]
    /// The provenance resolvedEntitlements() reports on success.
    var entitlementsSource: Qonversion.DeferredPurchase.EntitlementsSource = .backend
    private(set) var entitlementsCallsCount = 0
    private(set) var localFallbackTransactions: [[Qonversion.Transaction]] = []

    func entitlements() async throws -> [String: Qonversion.Entitlement] {
        return try await resolvedEntitlements().entitlements
    }

    func resolvedEntitlements() async throws -> ResolvedEntitlements {
        entitlementsCallsCount += 1
        if let entitlementsError { throw entitlementsError }
        return ResolvedEntitlements(entitlements: entitlementsResult, source: entitlementsSource)
    }

    func localFallbackEntitlements(for transactions: [Qonversion.Transaction]) async -> [String: Qonversion.Entitlement] {
        localFallbackTransactions.append(transactions)
        return localFallbackResult
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

    private(set) var deviceInfoCallsCount = 0
    private(set) var headerDeviceInfoCallsCount = 0

    func deviceInfo() -> Device {
        deviceInfoCallsCount += 1
        return device
    }

    func advertisingId() -> String? { advertisingIdValue }

    func headerDeviceInfo() -> HeaderDeviceInfo {
        headerDeviceInfoCallsCount += 1
        return HeaderDeviceInfo(
            appVersion: device.appVersion,
            country: device.country,
            language: device.language,
            osName: device.osName,
            osVersion: device.osVersion
        )
    }
}

final class MockDeviceService: DeviceServiceInterface {

    var current: Device?
    var createResult: Device?
    var updateResult: Device?
    var error: Error?
    var saveError: Error?
    var currentDeviceError: Error?

    private(set) var savedDevices: [Device] = []
    private(set) var removeStoredDeviceCallsCount = 0

    func removeStoredDevice() {
        removeStoredDeviceCallsCount += 1
        current = nil
    }
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

// MARK: - App transaction

final class MockAppTransactionReader: AppTransactionReaderInterface, @unchecked Sendable {

    var originalAppVersionResult: String?
    private(set) var callsCount = 0

    func originalAppVersion() async -> String? {
        callsCount += 1
        return originalAppVersionResult
    }
}
