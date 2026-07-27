//
//  DeviceServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

protocol DeviceServiceInterface {
    
    func save(device: Device) throws

    /// Drops the persisted device record (on a user switch the new user needs
    /// its own device row on the backend).
    func removeStoredDevice()

    func currentDevice() throws -> Device?
    
    func create(device: Device) async throws -> Device
    
    func update(device: Device) async throws -> Device
}
