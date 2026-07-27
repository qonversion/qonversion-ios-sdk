//
//  DeviceInfoCollectorInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 15.02.2024.
//

import Foundation

protocol DeviceInfoCollectorInterface: Sendable {
    
    func deviceInfo() -> Device
    
    func advertisingId() -> String?
}
