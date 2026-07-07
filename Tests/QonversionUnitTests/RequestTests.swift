//
//  RequestTests.swift
//  QonversionUnitTests
//
//  Fixation tests for Request.convertToURLRequest(_:) and the custom Hashable
//  implementation. These tests lock in CURRENT behavior, including quirks.
//

import XCTest
@testable import Qonversion

final class RequestTests: XCTestCase {

    private let baseURL = "https://api.qonversion.io/"

    // MARK: - Helpers

    private func bodyDict(_ request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request?.httpBody, "Expected non-nil httpBody")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func bodyArray(_ request: URLRequest?) throws -> [Any] {
        let data = try XCTUnwrap(request?.httpBody, "Expected non-nil httpBody")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
    }

    // MARK: - convertToURLRequest: every case

    func testGetUser() throws {
        let request = try XCTUnwrap(Request.getUser(id: "user1").convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/users/user1")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testCreateUser() throws {
        let body: RequestBodyDict = ["environment": "sandbox"]
        let request = try XCTUnwrap(Request.createUser(id: "user1", body: body).convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/users/user1")
        XCTAssertEqual(request.httpMethod, "POST")
        let decoded = try bodyDict(request)
        XCTAssertEqual(decoded["environment"] as? String, "sandbox")
        XCTAssertEqual(decoded.count, 1)
    }

    func testEntitlements() throws {
        let request = try XCTUnwrap(Request.entitlements(userId: "user1").convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/users/user1/entitlements")
        // Reading entitlements is a GET: POST on this route is the server-side
        // manual-grant API (secret key) and must never be sent by the SDK.
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testGetProperties() throws {
        let request = try XCTUnwrap(Request.getProperties(userId: "user1").convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/users/user1/properties")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testSendProperties() throws {
        let body: RequestBodyArray = [
            AnyHashable(["key": "_q_email", "value": "a@b.c"] as [String: String]),
        ]
        let request = try XCTUnwrap(Request.sendProperties(userId: "user1", body: body).convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/users/user1/properties")
        XCTAssertEqual(request.httpMethod, "POST")
        let decoded = try bodyArray(request)
        XCTAssertEqual(decoded.count, 1)
        let first = try XCTUnwrap(decoded.first as? [String: String])
        XCTAssertEqual(first, ["key": "_q_email", "value": "a@b.c"])
    }

    func testCreateDevice() throws {
        let request = try XCTUnwrap(Request.createDevice(userId: "user1", body: ["os": "iOS"]).convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/device/user1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try bodyDict(request)["os"] as? String, "iOS")
    }

    func testUpdateDevice() throws {
        let request = try XCTUnwrap(Request.updateDevice(userId: "user1", body: ["os": "iOS"]).convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/device/user1")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(try bodyDict(request)["os"] as? String, "iOS")
    }

    func testAppleSearchAds() throws {
        let request = try XCTUnwrap(Request.appleSearchAds(userId: "user1", body: ["token": "abc"]).convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/appleads/user1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try bodyDict(request)["token"] as? String, "abc")
    }

    func testGetProducts() throws {
        let request = try XCTUnwrap(Request.getProducts(userId: "user1").convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/products/user1")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testRemoteConfigWithoutContextKey() throws {
        let request = try XCTUnwrap(Request.remoteConfig(userId: "user1", contextKey: nil).convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/remote-config?user_id=user1")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testRemoteConfigWithContextKey() throws {
        let request = try XCTUnwrap(Request.remoteConfig(userId: "user1", contextKey: "main").convertToURLRequest(baseURL))
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/remote-config?user_id=user1&context_key=main")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testRemoteConfigList() throws {
        let request = try XCTUnwrap(
            Request.remoteConfigList(userId: "user1", contextKeys: ["a", "b"], includeEmptyContextKey: true)
                .convertToURLRequest(baseURL)
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.qonversion.io/v3/remote-configs?user_id=user1&with_empty_context_key=true&context_key=a&context_key=b"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testRemoteConfigListWithoutEmptyContextKey() throws {
        let request = try XCTUnwrap(
            Request.remoteConfigList(userId: "user1", contextKeys: [], includeEmptyContextKey: false)
                .convertToURLRequest(baseURL)
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.qonversion.io/v3/remote-configs?user_id=user1&with_empty_context_key=false"
        )
    }

    func testAllRemoteConfigList() throws {
        let request = try XCTUnwrap(Request.allRemoteConfigList(userId: "user1").convertToURLRequest(baseURL))
        // Fixates current behavior: the query string is baked into the default endpoint
        // and user_id is appended with "&".
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.qonversion.io/v3/remote-configs?all_context_keys=true&user_id=user1"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    func testAttachUserToExperiment() throws {
        let request = try XCTUnwrap(
            Request.attachUserToExperiment(userId: "user1", experimentId: "exp1", groupId: "group1")
                .convertToURLRequest(baseURL)
        )
        // Fixates current behavior: experimentId is substituted first, then userId.
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/experiments/exp1/users/user1")
        XCTAssertEqual(request.httpMethod, "POST")
        let decoded = try bodyDict(request)
        XCTAssertEqual(decoded["group_id"] as? String, "group1")
        XCTAssertEqual(decoded.count, 1)
    }

    func testDetachUserFromExperiment() throws {
        let request = try XCTUnwrap(
            Request.detachUserFromExperiment(userId: "user1", experimentId: "exp1").convertToURLRequest(baseURL)
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/experiments/exp1/users/user1")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.httpBody)
    }

    func testAttachUserToRemoteConfig() throws {
        let request = try XCTUnwrap(
            Request.attachUserToRemoteConfig(userId: "user1", remoteConfigId: "rc1").convertToURLRequest(baseURL)
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/remote-configurations/rc1/users/user1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.httpBody)
    }

    func testDetachUserFromRemoteConfig() throws {
        let request = try XCTUnwrap(
            Request.detachUserFromRemoteConfig(userId: "user1", remoteConfigId: "rc1").convertToURLRequest(baseURL)
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/remote-configurations/rc1/users/user1")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.httpBody)
    }

    // MARK: - URL building style (string concatenation, no explicit percent-encoding)

    func testUserIdWithSpaceIsAutoPercentEncodedByFoundation() throws {
        // The URL is built by naive string concatenation without explicit percent-encoding.
        // Fixates current behavior: on modern Foundation, URL(string:) auto-encodes invalid
        // characters, so a userId containing a space silently becomes "%20" in the URL
        // instead of failing (on older OS versions this would produce a nil URL request).
        let request = Request.getUser(id: "user with space").convertToURLRequest(baseURL)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.qonversion.io/v3/users/user%20with%20space")
    }

    func testContextKeyIsNotPercentEncodedManually() throws {
        // Fixates current behavior: query values are concatenated raw; "&" inside a context key
        // is NOT escaped and silently corrupts the query into an extra parameter.
        let request = try XCTUnwrap(
            Request.remoteConfig(userId: "u", contextKey: "a&b").convertToURLRequest(baseURL)
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v3/remote-config?user_id=u&context_key=a&b")
    }

    // MARK: - Hashable

    func testSameCaseAndParamsProduceEqualHashesAndEquality() {
        let a = Request.getUser(id: "user1")
        let b = Request.getUser(id: "user1")
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(a, b)

        let c = Request.createUser(id: "u", body: ["k": "v"])
        let d = Request.createUser(id: "u", body: ["k": "v"])
        XCTAssertEqual(c.hashValue, d.hashValue)
        XCTAssertEqual(c, d)
    }

    func testDifferentParamsProduceDifferentHashes() {
        XCTAssertNotEqual(Request.getUser(id: "user1").hashValue, Request.getUser(id: "user2").hashValue)
        XCTAssertNotEqual(
            Request.createUser(id: "u", body: ["k": "v1"]).hashValue,
            Request.createUser(id: "u", body: ["k": "v2"]).hashValue
        )
        XCTAssertNotEqual(
            Request.remoteConfig(userId: "u", contextKey: nil).hashValue,
            Request.remoteConfig(userId: "u", contextKey: "main").hashValue
        )
    }

    func testDifferentCasesWithSameParamsProduceDifferentHashes() {
        // Each case combines a distinct discriminator string into the hasher.
        XCTAssertNotEqual(Request.getUser(id: "user1").hashValue, Request.getProducts(userId: "user1").hashValue)
        XCTAssertNotEqual(
            Request.createDevice(userId: "u", body: ["k": "v"]).hashValue,
            Request.updateDevice(userId: "u", body: ["k": "v"]).hashValue
        )
    }

    func testAttachUserToExperimentHashIgnoresGroupId() {
        let a = Request.attachUserToExperiment(userId: "u", experimentId: "e", groupId: "group1")
        let b = Request.attachUserToExperiment(userId: "u", experimentId: "e", groupId: "group2")
        // Fixates current behavior: hash(into:) for attachUserToExperiment does NOT combine
        // groupId, so requests differing only in groupId get equal hashes while the
        // synthesized == still treats them as different values.
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, b)
    }
}
