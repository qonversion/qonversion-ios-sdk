//
//  DeviceManagerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for DeviceManager: lock in the current behavior as-is.
//

import XCTest
@testable import Qonversion

final class DeviceManagerTests: XCTestCase {

    private var deviceInfoCollector: MockDeviceInfoCollector!
    private var deviceService: MockDeviceService!
    private var manager: DeviceManager!

    override func setUp() {
        super.setUp()
        deviceInfoCollector = MockDeviceInfoCollector()
        deviceService = MockDeviceService()
        manager = DeviceManager(
            deviceInfoCollector: deviceInfoCollector,
            deviceService: deviceService,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        deviceService = nil
        deviceInfoCollector = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTestDevice(osVersion: String = "17.0", advertisingId: String? = nil) -> Device {
        return Device(
            manufacturer: "Apple",
            osName: "iOS",
            osVersion: osVersion,
            model: "iPhone15,2",
            appVersion: "1.2.3",
            country: "US",
            language: "en",
            timezone: "America/New_York",
            advertisingId: advertisingId,
            vendorId: "vendor-id",
            installDate: 1_700_000_000
        )
    }

    /// Polls a condition with short sleeps to observe fire-and-forget Tasks without long waits.
    private func waitForCondition(timeout: TimeInterval = 1.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
    }

    // MARK: - collectDeviceInfo

    func testCollectDeviceInfoCreatesDeviceWhenNoCurrentDevice() async {
        deviceInfoCollector.device = makeTestDevice()
        deviceService.current = nil
        let backendDevice = makeTestDevice(osVersion: "17.1")
        deviceService.createResult = backendDevice

        await manager.collectDeviceInfo()

        XCTAssertEqual(deviceService.createdDevices, [deviceInfoCollector.device])
        XCTAssertEqual(deviceService.updatedDevices, [])
        // The device returned by the service (not the collected one) is saved.
        XCTAssertEqual(deviceService.savedDevices, [backendDevice])
    }

    func testCollectDeviceInfoDoesNothingWhenDeviceUnchanged() async {
        deviceInfoCollector.device = makeTestDevice()
        deviceService.current = makeTestDevice()

        await manager.collectDeviceInfo()

        XCTAssertEqual(deviceService.createdDevices, [])
        XCTAssertEqual(deviceService.updatedDevices, [])
        XCTAssertEqual(deviceService.savedDevices, [])
    }

    func testCollectDeviceInfoUpdatesDeviceWhenChanged() async {
        deviceInfoCollector.device = makeTestDevice(osVersion: "18.0")
        deviceService.current = makeTestDevice(osVersion: "17.0")
        let backendDevice = makeTestDevice(osVersion: "18.0", advertisingId: "server-side-idfa")
        deviceService.updateResult = backendDevice

        await manager.collectDeviceInfo()

        XCTAssertEqual(deviceService.createdDevices, [])
        XCTAssertEqual(deviceService.updatedDevices, [deviceInfoCollector.device])
        XCTAssertEqual(deviceService.savedDevices, [backendDevice])
    }

    // Fixates current behavior: create/update errors are swallowed (only logged) and
    // nothing is saved locally.
    func testCollectDeviceInfoCreateErrorIsSwallowedAndNothingSaved() async {
        deviceService.current = nil
        deviceService.error = MockError.stubbed

        await manager.collectDeviceInfo()

        XCTAssertEqual(deviceService.createdDevices.count, 1)
        XCTAssertEqual(deviceService.savedDevices, [])
    }

    // MARK: - collectAdvertisingId

    func testCollectAdvertisingIdWithoutIdfaDoesNothing() {
        deviceInfoCollector.advertisingIdValue = nil

        manager.collectAdvertisingId()

        // Early return is synchronous — no Task is spawned, safe to assert immediately.
        XCTAssertEqual(deviceService.createdDevices, [])
        XCTAssertEqual(deviceService.updatedDevices, [])
        XCTAssertEqual(deviceService.savedDevices, [])
    }

    func testCollectAdvertisingIdAlreadyCollectedDoesNothing() async {
        deviceService.current = makeTestDevice(advertisingId: "idfa-value")
        deviceInfoCollector.advertisingIdValue = "idfa-value"

        manager.collectAdvertisingId()

        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        XCTAssertEqual(deviceService.createdDevices, [])
        XCTAssertEqual(deviceService.updatedDevices, [])
        XCTAssertEqual(deviceService.savedDevices, [])
    }

    func testCollectAdvertisingIdTriggersDeviceCreationWhenNoCurrentDevice() async {
        deviceService.current = nil
        deviceInfoCollector.advertisingIdValue = "idfa-value"
        deviceInfoCollector.device = makeTestDevice(advertisingId: "idfa-value")

        manager.collectAdvertisingId()

        await waitForCondition { self.deviceService.createdDevices.count == 1 }
        XCTAssertEqual(deviceService.createdDevices, [deviceInfoCollector.device])
    }

    func testCollectAdvertisingIdTriggersUpdateWhenDeviceInfoDiffers() async {
        deviceService.current = makeTestDevice(advertisingId: nil)
        deviceInfoCollector.advertisingIdValue = "idfa-value"
        deviceInfoCollector.device = makeTestDevice(advertisingId: "idfa-value")

        manager.collectAdvertisingId()

        await waitForCondition { self.deviceService.updatedDevices.count == 1 }
        XCTAssertEqual(deviceService.updatedDevices, [deviceInfoCollector.device])
        XCTAssertEqual(deviceService.createdDevices, [])
    }

    // Fixates current behavior: collectAdvertisingId only re-runs collectDeviceInfo, which
    // compares the freshly collected device info (NOT merged with the fresh IDFA) against
    // the stored device. If they are equal, neither create nor update is called, so the
    // new advertising id is never sent.
    func testCollectAdvertisingIdDoesNothingWhenCollectedInfoEqualsStoredDevice() async {
        deviceService.current = makeTestDevice(advertisingId: nil)
        deviceInfoCollector.device = makeTestDevice(advertisingId: nil)
        deviceInfoCollector.advertisingIdValue = "idfa-value"

        manager.collectAdvertisingId()

        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        XCTAssertEqual(deviceService.createdDevices, [])
        XCTAssertEqual(deviceService.updatedDevices, [])
        XCTAssertEqual(deviceService.savedDevices, [])
    }
}
