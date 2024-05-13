//
//  DeviceService.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

fileprivate enum Constants: String {
    case deviceKey = "device"
}

private enum DeviceRequestType {
    case create
    case update
}

final class DeviceService: DeviceServiceInterface {
    
    private let requestProcessor: RequestProcessorInterface
    private let localStorage: LocalStorageInterface
    private let userIdProvider: UserIdProvider
    private let encoder: JSONEncoder
    
    init(requestProcessor: RequestProcessorInterface, localStorage: LocalStorageInterface, userIdProvider: UserIdProvider, encoder: JSONEncoder) {
        self.requestProcessor = requestProcessor
        self.localStorage = localStorage
        self.userIdProvider = userIdProvider
        self.encoder = encoder
    }
    
    func save(device: Device) throws {
        try localStorage.set(device, forKey: deviceKey())
    }

    func currentDevice() throws -> Device? {
        guard let device = try localStorage.object(forKey: deviceKey(), dataType: Device.self) else { return nil }
        
        return device
    }
    
    func create(device: Device) async throws -> Device {
        return try await processDeviceRequest(for: device, requestType: .create)
    }
    
    func update(device: Device) async throws -> Device {
        return try await processDeviceRequest(for: device, requestType: .update)
    }
    
}

// MARK: - Private

extension DeviceService {
    
    private func deviceKey() -> String {
        return InternalConstants.storagePrefix.rawValue + Constants.deviceKey.rawValue
    }
    
    private func serialize(device: Device) -> RequestBodyDict? {
        guard let data: Data = try? encoder.encode(device) else { return nil }

        let body: RequestBodyDict? = try? JSONSerialization.jsonObject(with: data, options: []) as? RequestBodyDict
        
        return body
    }
    
    private func processDeviceRequest(for device: Device, requestType: DeviceRequestType) async throws -> Device {
        guard let body: RequestBodyDict = serialize(device: device) else {
            throw QonversionError.init(type: .unableToSerializeDevice)
        }
        
        let request: Request
        let errorType: QonversionErrorType
        
        switch requestType {
        case .create:
            request = Request.createDevice(userId: userIdProvider.getUserId(), body: body)
            errorType = .deviceCreationFailed
        case .update:
            request = Request.updateDevice(userId: userIdProvider.getUserId(), body: body)
            errorType = .deviceUpdateFailed
        }
        
        do {
            let device: Device = try await requestProcessor.process(request: request, responseType: Device.self)
            
            return device
        } catch {
            throw QonversionError(type: errorType, message: nil, error: error)
        }
    }
}
