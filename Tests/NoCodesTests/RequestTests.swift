//
//  RequestTests.swift
//  NoCodesTests
//
//  URL composition, path escaping and the header set every request carries.
//

import XCTest
@testable import NoCodes

private final class StubDeviceInfoCollector: DeviceInfoCollectorInterface, Sendable {

    private let device: Device

    init(device: Device) {
        self.device = device
    }

    func deviceInfo() -> Device {
        return device
    }
}

final class RequestTests: XCTestCase {

    private let baseURL = "https://api2.qonversion.io/"

    // MARK: - URL composition

    func testGetScreenByIdTargetsTheScreensEndpoint() throws {
        let request = Request.getScreen(id: "screen-1")

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/screens/screen-1")
        XCTAssertEqual(urlRequest.httpMethod, "GET")
        XCTAssertNil(urlRequest.httpBody)
    }

    func testGetScreenByContextKeyTargetsTheContextsEndpoint() throws {
        let request = Request.getScreenByContextKey(contextKey: "main")

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/contexts/main/screens")
        XCTAssertEqual(urlRequest.httpMethod, "GET")
    }

    func testPreloadScreensCarriesThePreloadQuery() throws {
        let request = Request.getPreloadScreens()

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/screens?preload=true")
        XCTAssertEqual(urlRequest.httpMethod, "GET")
    }

    func testScreenEventsPostsTheEventsEnvelopeForTheUser() throws {
        let events: [[String: AnyHashable]] = [["type": "screen_shown", "screen_uid": "screen-1"]]
        let request = Request.sendScreenEvents(uid: "user-1", body: events)

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/users/user-1/screen-events")
        XCTAssertEqual(urlRequest.httpMethod, "POST")

        let body: Data = try XCTUnwrap(urlRequest.httpBody)
        let decoded: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sentEvents: [[String: Any]] = try XCTUnwrap(decoded["events"] as? [[String: Any]])
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents.first?["type"] as? String, "screen_shown")
    }

    // MARK: - Path escaping

    func testHostilePathComponentsCannotEscapeTheirSegment() {
        let encoded: String = Request.encodedPathComponent("ctx key/©?#")

        // Every character that would retarget the request has to be escaped:
        // the slash, the query marker and the fragment marker.
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("?"))
        XCTAssertFalse(encoded.contains("#"))
        XCTAssertFalse(encoded.contains(" "))
        XCTAssertEqual(encoded, "ctx%20key%2F%C2%A9%3F%23")
    }

    func testScreenIdIsEscapedIntoASingleSegment() throws {
        let request = Request.getScreen(id: "../../v3/admin")

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/screens/..%2F..%2Fv3%2Fadmin")
    }

    func testContextKeyIsEscapedIntoASingleSegment() throws {
        let request = Request.getScreenByContextKey(contextKey: "ctx key/©?#")

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/contexts/ctx%20key%2F%C2%A9%3F%23/screens")
    }

    func testUserIdIsEscapedIntoASingleSegment() throws {
        let events: [[String: AnyHashable]] = [["type": "screen_shown"]]
        let request = Request.sendScreenEvents(uid: "user/1?x=2", body: events)

        let urlRequest: URLRequest = try XCTUnwrap(request.convertToURLRequest(baseURL))

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api2.qonversion.io/v3/users/user%2F1%3Fx=2/screen-events")
    }

    func testAlreadySafeComponentsAreLeftAlone() {
        let encoded: String = Request.encodedPathComponent("main_screen-1")

        XCTAssertEqual(encoded, "main_screen-1")
    }

    // MARK: - Headers

    func testHeadersCarryTheProjectKeyAsABearerTokenAndTheDeviceContext() {
        let device: Device = makeDevice()
        let deviceInfoCollector = StubDeviceInfoCollector(device: device)
        let headersBuilder = HeadersBuilder(projectKey: "project-key", deviceInfoCollector: deviceInfoCollector)
        let url = URL(string: "https://api2.qonversion.io/v3/screens/screen-1")!
        var request = URLRequest(url: url)

        headersBuilder.addHeaders(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer project-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(request.value(forHTTPHeaderField: "app-version"), "1.2.3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "country"), "US")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Locale"), "en")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Platform"), "iOS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Platform-Version"), "17.4")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Source"), UserDefaults.source)
    }

    func testMissingOptionalDeviceValuesBecomeEmptyHeaders() {
        let device: Device = makeDevice(appVersion: nil, country: nil, language: nil)
        let deviceInfoCollector = StubDeviceInfoCollector(device: device)
        let headersBuilder = HeadersBuilder(projectKey: "project-key", deviceInfoCollector: deviceInfoCollector)
        let url = URL(string: "https://api2.qonversion.io/v3/screens/screen-1")!
        var request = URLRequest(url: url)

        headersBuilder.addHeaders(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "app-version"), "")
        XCTAssertEqual(request.value(forHTTPHeaderField: "country"), "")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Locale"), "")
    }

    // MARK: - Private

    private func makeDevice(appVersion: String? = "1.2.3", country: String? = "US", language: String? = "en") -> Device {
        return Device(
            manufacturer: "Apple",
            osName: "iOS",
            osVersion: "17.4",
            model: "iPhone15,2",
            appVersion: appVersion,
            country: country,
            language: language,
            timezone: "Europe/Berlin",
            vendorId: "vendor-1",
            installDate: 1700000000
        )
    }
}
