//
//  DeviceInfoCollectorInterface.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 15.02.2024.
//

import Foundation

#if os(iOS)

protocol DeviceInfoCollectorInterface {
    
    func deviceInfo() -> Device
    
    func advertisingId() -> String?
}

#endif
