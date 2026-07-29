//
//  DeviceManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

// @unchecked: the collect chain is guarded by chainLock; deps are thread-safe.
final class DeviceManager: DeviceManagerInterface, @unchecked Sendable {

    private let deviceInfoCollector: DeviceInfoCollectorInterface
    private let deviceService: DeviceServiceInterface
    private let logger: LoggerWrapper

    private let chainLock = NSLock()
    /// The last enqueued collect pass. A pass decides create-or-update from a
    /// snapshot the previous one has not persisted yet, so two of them running
    /// at once both see "no device" and create the row twice.
    private var lastCollect: Task<Void, Never>?

    init(deviceInfoCollector: DeviceInfoCollectorInterface, deviceService: DeviceServiceInterface, logger: LoggerWrapper) {
        self.deviceInfoCollector = deviceInfoCollector
        self.deviceService = deviceService
        self.logger = logger
    }

    func collectDeviceInfo() async {
        await enqueueCollect().value
    }

    func clearStoredDevice() {
        deviceService.removeStoredDevice()
    }

    func collectAdvertisingId() {
        let currentDevice: Device? = currentDevice()
        let advertisingId: String? = deviceInfoCollector.advertisingId()

        guard let advertisingId else {
            return logger.warning(LoggerInfoMessages.advertisingIdUnavailable.rawValue)
        }

        guard currentDevice?.advertisingId != advertisingId else {
            return logger.info(LoggerInfoMessages.advertisingIdAlreadyCollected.rawValue)
        }

        Task {
            await collectDeviceInfo()
        }
    }

}

// MARK: - Private

extension DeviceManager {

    /// Chains onto the pass already queued, so the passes run one after
    /// another and each of them sees what the previous one persisted.
    private func enqueueCollect() -> Task<Void, Never> {
        chainLock.lock()
        defer { chainLock.unlock() }

        let previous: Task<Void, Never>? = lastCollect
        let task = Task<Void, Never> { [weak self] in
            await previous?.value
            await self?.performCollect()
        }
        lastCollect = task

        return task
    }

    private func performCollect() async {
        let deviceInfo: Device = deviceInfoCollector.deviceInfo()

        let currentDevice: Device? = currentDevice()

        if currentDevice == nil {
            return await create(deviceInfo: deviceInfo)
        }

        guard deviceInfo != currentDevice else { return }

        return await update(deviceInfo: deviceInfo)
    }

    /// Both paths persist the snapshot that was SENT, not the record the
    /// endpoint echoed back: the stored copy is only ever compared against the
    /// next local collection, and an echo differing in any field (a
    /// server-side advertising id, a normalised value, a truncated answer)
    /// would make that comparison non-empty on every launch from then on.
    private func create(deviceInfo: Device) async {
        do {
            _ = try await deviceService.create(device: deviceInfo)
            try deviceService.save(device: deviceInfo)
            return logger.info(LoggerInfoMessages.deviceCreated.rawValue)
        } catch {
            return logger.warning("Failed to create device: " + error.message)
        }
    }

    private func update(deviceInfo: Device) async {
        do {
            _ = try await deviceService.update(device: deviceInfo)
            try deviceService.save(device: deviceInfo)
            return logger.info(LoggerInfoMessages.deviceUpdated.rawValue)
        } catch {
            return logger.warning("Failed to update device: " + error.message)
        }
    }

    private func currentDevice() -> Device? {
        var currentDevice: Device? = nil
        do {
            currentDevice = try deviceService.currentDevice()
        } catch {
            logger.error("Failed to load current device from storage: " + error.message)
        }
        return currentDevice
    }
}

// MARK: - UserChangedObserver

extension DeviceManager: UserChangedObserver {

    func userDidChange() {
        // The stored record belongs to the previous user — drop it and
        // create the new user's device row right away, not on the next launch.
        clearStoredDevice()
        Task { [weak self] in
            await self?.collectDeviceInfo()
        }
    }
}
