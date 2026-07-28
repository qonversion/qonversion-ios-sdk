//
//  DeviceServiceTests.swift
//  QonversionUnitTests
//
//  Fixation tests for DeviceService: locks in current behavior as-is.
//

import XCTest
@testable import Qonversion

final class DeviceServiceTests: XCTestCase {

    private let userId = "QON_device_user"
    private let expectedDeviceStorageKey = "io.qonversion.sdk.storage.device"

    // MARK: - Helpers

    private func makeService(
        processor: MockRequestProcessor = MockRequestProcessor(),
        storage: MockLocalStorage = MockLocalStorage()
    ) -> DeviceService {
        DeviceService(
            requestProcessor: processor,
            localStorage: storage,
            userIdProvider: InternalConfig(userId: userId),
            encoder: JSONEncoder()
        )
    }

    private func makeDevice(
        model: String? = "iPhone15,2",
        advertisingId: String? = nil,
        installDate: TimeInterval = 1_700_000_000
    ) -> Device {
        Device(
            osName: "iOS",
            osVersion: "17.0",
            model: model,
            appVersion: "1.2.3",
            country: "US",
            language: "en",
            advertisingId: advertisingId,
            vendorId: "vendor-id",
            installDate: installDate
        )
    }

    // MARK: - save / currentDevice

    func testSaveEncodesDeviceToDataUnderPrefixedKey() throws {
        let storage = MockLocalStorage()
        let service = makeService(storage: storage)
        let device = makeDevice()

        try service.save(device: device)

        // The device is persisted through the typed Codable helper as Data —
        // safe for a real UserDefaults-backed storage.
        XCTAssertNotNil(storage.storage[expectedDeviceStorageKey] as? Data)
    }

    func testCurrentDeviceReturnsSavedDevice() throws {
        let storage = MockLocalStorage()
        let service = makeService(storage: storage)
        let device = makeDevice()

        try service.save(device: device)

        XCTAssertEqual(try service.currentDevice(), device)
    }

    func testCurrentDeviceReturnsNilWhenNothingSaved() throws {
        let service = makeService()

        XCTAssertNil(try service.currentDevice())
    }

    // MARK: - create

    func testCreateSendsCreateDeviceRequestWithSerializedBody() async throws {
        let processor = MockRequestProcessor()
        let service = makeService(processor: processor)
        let responseDevice = makeDevice(model: "iPhone16,1")
        processor.results = [responseDevice]

        let result = try await service.create(device: makeDevice(advertisingId: "ad-id"))

        XCTAssertEqual(result, responseDevice)
        XCTAssertEqual(processor.processedRequests.count, 1)
        guard case let .createDevice(requestUserId, endpoint, body, type) = processor.processedRequests[0] else {
            return XCTFail("Expected createDevice request, got \(processor.processedRequests[0])")
        }
        XCTAssertEqual(requestUserId, userId)
        XCTAssertEqual(endpoint, "v4/users/%@/device")
        XCTAssertEqual(type, .post)
        XCTAssertEqual(body["os_name"] as? String, "iOS")
        XCTAssertEqual(body["os_version"] as? String, "17.0")
        XCTAssertEqual(body["model"] as? String, "iPhone15,2")
        XCTAssertEqual(body["app_version"] as? String, "1.2.3")
        XCTAssertEqual(body["country"] as? String, "US")
        XCTAssertEqual(body["language"] as? String, "en")
        XCTAssertEqual(body["advertising_id"] as? String, "ad-id")
        XCTAssertEqual(body["vendor_id"] as? String, "vendor-id")
        XCTAssertEqual(body["install_date"] as? Int, 1_700_000_000)
    }

    func testTheWireBodyIsExactlyTheAgreedKeySet() async throws {
        // The canonical device body. Any key added, renamed or dropped here is
        // a contract break with the backend, which implements the same set.
        let processor = MockRequestProcessor()
        let service = makeService(processor: processor)
        processor.results = [makeDevice()]

        _ = try await service.create(device: makeDevice(advertisingId: "ad-id"))

        guard case let .createDevice(_, _, body, _) = processor.processedRequests[0] else {
            return XCTFail("Expected createDevice request")
        }
        let expectedKeys: Set<String> = [
            "os_name",
            "os_version",
            "model",
            "app_version",
            "country",
            "language",
            "advertising_id",
            "vendor_id",
            "install_date"
        ]
        XCTAssertEqual(Set(body.keys), expectedKeys)
    }

    func testTheInstallDateTravelsAsUnixSeconds() async throws {
        let processor = MockRequestProcessor()
        let service = makeService(processor: processor)
        processor.results = [makeDevice()]

        _ = try await service.create(device: makeDevice(installDate: 1_700_000_000.75))

        guard case let .createDevice(_, _, body, _) = processor.processedRequests[0] else {
            return XCTFail("Expected createDevice request")
        }
        // An integer, not a fractional double: the backend column is seconds.
        XCTAssertEqual(body["install_date"] as? Int, 1_700_000_000)
    }

    func testTheEchoedRecordDecodesFromTheSameKeys() throws {
        // The endpoint answers with the object it was sent — same keys.
        let echo = Data("""
        {"os_name":"iOS","os_version":"17.0","model":"iPhone15,2","app_version":"1.2.3",\
        "country":"US","language":"en","advertising_id":"ad-id","vendor_id":"vendor-id",\
        "install_date":1700000000}
        """.utf8)

        let device: Device = try JSONDecoder().decode(Device.self, from: echo)

        XCTAssertEqual(device.osName, "iOS")
        XCTAssertEqual(device.advertisingId, "ad-id")
        XCTAssertEqual(device.installDate, 1_700_000_000)
    }

    func testATruncatedEchoStillDecodes() throws {
        // A record the SDK just created must not be lost to a partial answer.
        let echo = Data(#"{"os_name":"iOS"}"#.utf8)

        let device: Device = try JSONDecoder().decode(Device.self, from: echo)

        XCTAssertEqual(device.osName, "iOS")
        XCTAssertEqual(device.osVersion, "")
        XCTAssertNil(device.vendorId)
    }

    func testCreateOmitsNilOptionalFieldsFromBody() async throws {
        let processor = MockRequestProcessor()
        let service = makeService(processor: processor)
        processor.results = [makeDevice()]

        _ = try await service.create(device: makeDevice(model: nil, advertisingId: nil))

        guard case let .createDevice(_, _, body, _) = processor.processedRequests[0] else {
            return XCTFail("Expected createDevice request")
        }
        XCTAssertNil(body["model"])
        XCTAssertNil(body["advertising_id"])
    }

    func testCreateWrapsProcessorErrorIntoDeviceCreationFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        do {
            _ = try await service.create(device: makeDevice())
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .deviceCreationFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    // MARK: - update

    func testUpdateSendsUpdateDeviceRequest() async throws {
        let processor = MockRequestProcessor()
        let service = makeService(processor: processor)
        let responseDevice = makeDevice(model: "iPhone16,2")
        processor.results = [responseDevice]

        let result = try await service.update(device: makeDevice())

        XCTAssertEqual(result, responseDevice)
        XCTAssertEqual(processor.processedRequests.count, 1)
        guard case let .updateDevice(requestUserId, endpoint, body, type) = processor.processedRequests[0] else {
            return XCTFail("Expected updateDevice request, got \(processor.processedRequests[0])")
        }
        XCTAssertEqual(requestUserId, userId)
        XCTAssertEqual(endpoint, "v4/users/%@/device")
        XCTAssertEqual(type, .put)
        XCTAssertEqual(body["os_name"] as? String, "iOS")
    }

    func testUpdateWrapsProcessorErrorIntoDeviceUpdateFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor: processor)

        do {
            _ = try await service.update(device: makeDevice())
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .deviceUpdateFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    // MARK: - serialization failure

    func testCreateThrowsUnableToSerializeDeviceWhenEncodingFails() async {
        let processor = MockRequestProcessor()
        let service = makeService(processor: processor)
        // JSONEncoder fails on non-conforming floats (infinity) without a special strategy.
        let unserializableDevice = makeDevice(installDate: .infinity)

        do {
            _ = try await service.create(device: unserializableDevice)
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .unableToSerializeDevice)
            // No request is sent when serialization fails.
            XCTAssertTrue(processor.processedRequests.isEmpty)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }
}

// MARK: - platform reported to the backend

final class DevicePlatformTests: XCTestCase {

    func testThePlatformIsTheOneThisBuildRunsOn() {
        // The value is part of the v4 contract; visionOS used to report as iOS.
        let collector = DeviceInfoCollector()

        let osName: String = collector.deviceInfo().osName

        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(osName, "macCatalyst")
        #elseif os(macOS)
        XCTAssertEqual(osName, "macOS")
        #elseif os(tvOS)
        XCTAssertEqual(osName, "tvOS")
        #elseif os(watchOS)
        XCTAssertEqual(osName, "watchOS")
        #elseif os(visionOS)
        XCTAssertEqual(osName, "visionOS")
        #else
        XCTAssertEqual(osName, "iOS")
        #endif
    }

    func testTheHeaderCarriesTheSamePlatformAsTheDeviceRecord() {
        let collector = DeviceInfoCollector()

        XCTAssertEqual(collector.headerDeviceInfo().osName, collector.deviceInfo().osName)
    }

    func testCountryAndLanguageStayIsoIdentifiers() {
        // Owner decision: ISO country and language codes ARE the v4 contract.
        let device: Device = DeviceInfoCollector().deviceInfo()

        if let country: String = device.country {
            XCTAssertEqual(country, country.uppercased())
            XCTAssertEqual(country.count, 2)
        }
        if let language: String = device.language {
            XCTAssertEqual(language, language.lowercased())
        }
    }
}
