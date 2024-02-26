//
//  HeadersBuilder.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

class HeadersBuilder: HeadersBuilderInterface {
    
    let apiKey: String
    let sdkVersion: String
    let device: Device
    
    init(apiKey: String, sdkVersion: String, device: Device) {
        self.apiKey = apiKey
        self.sdkVersion = sdkVersion
        self.device = device
    }
    
    func addHeaders(to request: inout URLRequest) {
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: Header.contentType.rawValue)
        request.addValue("Bearer " + apiKey, forHTTPHeaderField: Header.authorization.rawValue)
        request.addValue(device.appVersion ?? "", forHTTPHeaderField: Header.appVersion.rawValue)
        request.addValue(device.country ?? "", forHTTPHeaderField: Header.country.rawValue)
        request.addValue(device.language ?? "", forHTTPHeaderField: Header.userLocale.rawValue)
        #warning("use value from UserDefaults")
        request.addValue("iOS", forHTTPHeaderField: Header.source.rawValue)
        #warning("use value from UserDefaults")
        request.addValue(sdkVersion, forHTTPHeaderField: Header.sourceVersion.rawValue)
        request.addValue(device.osName, forHTTPHeaderField: Header.platform.rawValue)
        request.addValue(device.osVersion, forHTTPHeaderField: Header.platformVersion.rawValue)
    }
}
