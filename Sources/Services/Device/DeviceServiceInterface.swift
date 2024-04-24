//
//  DeviceServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

protocol DeviceServiceInterface {
    
    func save(device: Device)
    
    func currentDevice() -> Device?
    
    func create(device: Device) async throws -> Device
    
    func update(device: Device) async throws -> Device
}
