//
//  DeviceManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

final class DeviceManager: DeviceManagerInterface {
    
    private let deviceInfoCollector: DeviceInfoCollectorInterface
    private let deviceService: DeviceServiceInterface
    private let logger: LoggerWrapper
    
    init(deviceInfoCollector: DeviceInfoCollectorInterface, deviceService: DeviceServiceInterface, logger: LoggerWrapper) {
        self.deviceInfoCollector = deviceInfoCollector
        self.deviceService = deviceService
        self.logger = logger
    }
    
    func collectDeviceInfo() async {
        let deviceInfo: Device = deviceInfoCollector.deviceInfo()

        let currentDevice: Device? = currentDevice()
        
        if currentDevice == nil {
            return await create(deviceInfo: deviceInfo)
        }
        
        guard deviceInfo != currentDevice else { return }
        
        return await update(deviceInfo: deviceInfo)
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
    
    private func create(deviceInfo: Device) async {
        do {
            let device: Device = try await deviceService.create(device: deviceInfo)
            try deviceService.save(device: device)
            return logger.info(LoggerInfoMessages.deviceCreated.rawValue)
        } catch {
            logger.warning("Failed to create device: " + error.message)
        }
    }
    
    private func update(deviceInfo: Device) async {
        do {
            let device: Device = try await deviceService.update(device: deviceInfo)
            try deviceService.save(device: device)
            return logger.info(LoggerInfoMessages.deviceUpdated.rawValue)
        } catch {
            logger.warning("Failed to update device: " + error.message)
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
