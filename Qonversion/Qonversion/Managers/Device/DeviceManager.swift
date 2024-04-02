//
//  DeviceManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

final class DeviceManager: DeviceManagerInterface {
    
    let deviceInfoCollector: DeviceInfoCollectorInterface
    let deviceService: DeviceServiceInterface
    let logger: LoggerWrapper
    
    init(deviceInfoCollector: DeviceInfoCollectorInterface, deviceService: DeviceServiceInterface, logger: LoggerWrapper) {
        self.deviceInfoCollector = deviceInfoCollector
        self.deviceService = deviceService
        self.logger = logger
    }
    
    func collectDeviceInfo() async {
        let deviceInfo = deviceInfoCollector.deviceInfo()

        let currentDevice: Device? = deviceService.currentDevice()
        
        if currentDevice == nil {
            do {
                let device: Device = try await deviceService.create(device: deviceInfo)
                deviceService.save(device: device)
                logger.info(LoggerInfoMessages.deviceCreated.rawValue)
            } catch {
                logger.warning(error.localizedDescription)
            }
        }
        
        guard deviceInfo != currentDevice else { return }
        
        do {
            let device: Device = try await deviceService.update(device: deviceInfo)
            deviceService.save(device: device)
            logger.info(LoggerInfoMessages.deviceUpdated.rawValue)
        } catch {
            logger.warning(error.localizedDescription)
        }
    }
    
    func collectAdvertisingId() {
        let currentDevice: Device? = deviceService.currentDevice()
        let advertisingId: String? = deviceInfoCollector.advertisingId()
        
        guard let advertisingId else {
            return logger.warning(LoggerInfoMessages.advertisingIdUnavailable.rawValue)
        }
        
        guard currentDevice?.advertisingId != advertisingId else {
            return logger.info(LoggerInfoMessages.advertisingAlreadyCollected.rawValue)
        }
        
        Task {
            await collectDeviceInfo()
        }
    }
    
}
