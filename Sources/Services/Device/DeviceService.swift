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
    private let localStorage: LocalStorage
    private let userIdProvider: UserIdProvider
    private let encoder: JSONEncoder
    
    init(requestProcessor: RequestProcessorInterface, localStorage: LocalStorage, userIdProvider: UserIdProvider, encoder: JSONEncoder) {
        self.requestProcessor = requestProcessor
        self.localStorage = localStorage
        self.userIdProvider = userIdProvider
        self.encoder = encoder
    }
    
    func save(device: Qonversion.Device) {
        localStorage.set(device, forKey: deviceKey())
    }
    
    func currentDevice() -> Qonversion.Device? {
        guard let device = localStorage.object(forKey: deviceKey()) as? Qonversion.Device else { return nil }
        
        return device
    }
    
    func create(device: Qonversion.Device) async throws -> Qonversion.Device {
        return try await processDeviceRequest(for: device, requestType: .create)
    }
    
    func update(device: Qonversion.Device) async throws -> Qonversion.Device {
        return try await processDeviceRequest(for: device, requestType: .update)
    }
    
}

// MARK: - Private

extension DeviceService {
    
    private func deviceKey() -> String {
        return InternalConstants.storagePrefix.rawValue + Constants.deviceKey.rawValue
    }
    
    private func serialize(device: Qonversion.Device) -> RequestBodyDict? {
        guard let data: Data = try? encoder.encode(device) else { return nil }

        let body: RequestBodyDict? = try? JSONSerialization.jsonObject(with: data, options: []) as? RequestBodyDict
        
        return body
    }
    
    private func processDeviceRequest(for device: Qonversion.Device, requestType: DeviceRequestType) async throws -> Qonversion.Device {
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
            let device: Qonversion.Device = try await requestProcessor.process(request: request, responseType: Qonversion.Device.self)
            
            return device
        } catch {
            throw QonversionError(type: errorType, message: nil, error: error)
        }
    }
    
}
