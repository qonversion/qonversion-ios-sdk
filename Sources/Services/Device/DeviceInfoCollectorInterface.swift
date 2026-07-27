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

    /// The five request-header fields only — no IDFA/IDFV/model work, safe to
    /// call on every request from any thread.
    func headerDeviceInfo() -> HeaderDeviceInfo
}

/// The cheap slice of device info the request headers need.
struct HeaderDeviceInfo: Sendable {
    let appVersion: String?
    let country: String?
    let language: String?
    let osName: String
    let osVersion: String
}
