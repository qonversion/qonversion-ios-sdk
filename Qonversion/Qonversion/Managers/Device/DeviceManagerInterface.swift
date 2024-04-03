//
//  DeviceManagerInterface.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 02.04.2024.
//

import Foundation

protocol DeviceManagerInterface {
    
    func collectDeviceInfo() async
    
    func collectAdvertisingId()
    
}
