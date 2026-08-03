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

    func testUserChangeDropsTheStoredDeviceRecord() {
        deviceService.current = Device(
            osName: "iOS", osVersion: "17.0", model: "iPhone15,2",
            appVersion: "1.0", country: "US", language: "en",
            advertisingId: nil, vendorId: "v", installDate: 1
        )

        manager.userDidChange()

        XCTAssertEqual(deviceService.removeStoredDeviceCallsCount, 1, "the new user needs its own device row on the backend")
    }

    // A pass started for the previous user must still reach the backend, but
    // its snapshot must not land in storage after a switch already cleared
    // the record — or the new user's own create() would be overwritten right
    // back to the departing user's device.
    func testAPassInFlightWhenTheUserSwitchesDoesNotOverwriteTheNewUsersRecord() async {
        let previousUserDevice = makeTestDevice(osVersion: "17.0")
        deviceInfoCollector.device = previousUserDevice
        deviceService.current = nil
        deviceService.onCreate = { try? await Task.sleep(nanoseconds: 100_000_000) }

        async let firstPass: Void = manager.collectDeviceInfo()
        await waitForCondition { self.deviceService.createdDevices.count >= 1 }

        manager.userDidChange()
        deviceInfoCollector.device = makeTestDevice(osVersion: "18.0")
        await firstPass

        XCTAssertEqual(deviceService.savedDevices, [], "the previous user's snapshot must not be persisted after the switch cleared the record")
    }

    func testTheUserSwitchsOwnPassStillPersistsAfterAStalePassCompletes() async {
        let previousUserDevice = makeTestDevice(osVersion: "17.0")
        deviceInfoCollector.device = previousUserDevice
        deviceService.current = nil
        deviceService.onCreate = { try? await Task.sleep(nanoseconds: 100_000_000) }

        async let firstPass: Void = manager.collectDeviceInfo()
        await waitForCondition { self.deviceService.createdDevices.count >= 1 }

        manager.userDidChange()
        let newUserDevice = makeTestDevice(osVersion: "18.0")
        deviceInfoCollector.device = newUserDevice
        await firstPass
        await waitForCondition(timeout: 2.0) { self.deviceService.savedDevices.count >= 1 }

        XCTAssertEqual(deviceService.savedDevices, [newUserDevice], "the new user still gets its own device row persisted")
    }

    // MARK: - Helpers

    private func makeTestDevice(osVersion: String = "17.0", advertisingId: String? = nil) -> Device {
        return Device(
            osName: "iOS",
            osVersion: osVersion,
            model: "iPhone15,2",
            appVersion: "1.2.3",
            country: "US",
            language: "en",
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
        // The snapshot that was SENT is what the next diff is judged against —
        // an echo that differs would make every launch send an update.
        XCTAssertEqual(deviceService.savedDevices, [deviceInfoCollector.device])
        XCTAssertNotEqual(backendDevice, deviceInfoCollector.device)
    }

    func testASecondPassAfterASuccessfulCreateSendsNothing() async {
        deviceInfoCollector.device = makeTestDevice()
        deviceService.current = nil
        // The backend enriches the record it echoes back.
        deviceService.createResult = makeTestDevice(advertisingId: "server-side-idfa")

        await manager.collectDeviceInfo()
        await manager.collectDeviceInfo()

        XCTAssertEqual(deviceService.createdDevices.count, 1)
        XCTAssertEqual(deviceService.updatedDevices, [], "an unchanged device must not cost a request on every launch")
    }

    func testASecondPassAfterASuccessfulUpdateSendsNothing() async {
        deviceInfoCollector.device = makeTestDevice(osVersion: "18.0")
        deviceService.current = makeTestDevice(osVersion: "17.0")
        deviceService.updateResult = makeTestDevice(osVersion: "18.0", advertisingId: "server-side-idfa")

        await manager.collectDeviceInfo()
        await manager.collectDeviceInfo()

        XCTAssertEqual(deviceService.updatedDevices.count, 1)
        XCTAssertEqual(deviceService.createdDevices, [])
    }

    func testConcurrentPassesCreateTheDeviceOnlyOnce() async {
        // README-recommended sequence: launch starts a collect pass and the ATT
        // callback starts another one while the first is still in flight.
        deviceInfoCollector.device = makeTestDevice()
        deviceService.current = nil
        deviceService.onCreate = { try? await Task.sleep(nanoseconds: 50_000_000) }

        async let first: Void = manager.collectDeviceInfo()
        async let second: Void = manager.collectDeviceInfo()
        _ = await (first, second)

        XCTAssertEqual(deviceService.createdDevices.count, 1, "two device rows for one device is a duplicate the backend cannot merge")
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
        XCTAssertEqual(deviceService.savedDevices, [deviceInfoCollector.device])
        XCTAssertNotEqual(backendDevice, deviceInfoCollector.device)
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
