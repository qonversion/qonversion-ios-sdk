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
            manufacturer: "Apple",
            osName: "iOS",
            osVersion: "17.0",
            model: model,
            appVersion: "1.2.3",
            country: "US",
            language: "en",
            timezone: "America/New_York",
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
        XCTAssertEqual(body["manufacturer"] as? String, "Apple")
        XCTAssertEqual(body["osName"] as? String, "iOS")
        XCTAssertEqual(body["osVersion"] as? String, "17.0")
        XCTAssertEqual(body["model"] as? String, "iPhone15,2")
        XCTAssertEqual(body["appVersion"] as? String, "1.2.3")
        XCTAssertEqual(body["country"] as? String, "US")
        XCTAssertEqual(body["language"] as? String, "en")
        XCTAssertEqual(body["timezone"] as? String, "America/New_York")
        XCTAssertEqual(body["advertisingId"] as? String, "ad-id")
        XCTAssertEqual(body["vendorId"] as? String, "vendor-id")
        XCTAssertEqual(body["installDate"] as? TimeInterval, 1_700_000_000)
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
        XCTAssertNil(body["advertisingId"])
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
        XCTAssertEqual(body["manufacturer"] as? String, "Apple")
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
