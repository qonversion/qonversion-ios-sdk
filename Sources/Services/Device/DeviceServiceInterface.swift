//
//  DeviceServiceInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

protocol DeviceServiceInterface {
    
    func save(device: Qonversion.Device)
    
    func currentDevice() -> Qonversion.Device?
    
    func create(device: Qonversion.Device) async throws -> Qonversion.Device
    
    func update(device: Qonversion.Device) async throws -> Qonversion.Device
    
}
