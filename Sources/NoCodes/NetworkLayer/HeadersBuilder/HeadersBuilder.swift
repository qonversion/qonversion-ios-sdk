//
//  HeadersBuilder.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

#if os(iOS)

class HeadersBuilder: HeadersBuilderInterface {
    
    let projectKey: String
    let sdkVersion: String
    let deviceInfoCollector: DeviceInfoCollectorInterface
    
    init(projectKey: String, sdkVersion: String, deviceInfoCollector: DeviceInfoCollectorInterface) {
        self.projectKey = projectKey
        self.sdkVersion = sdkVersion
        self.deviceInfoCollector = deviceInfoCollector
    }
    
    func addHeaders(to request: inout URLRequest) {
        let device = deviceInfoCollector.deviceInfo()
        
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: Header.contentType.rawValue)
        request.addValue("Bearer " + projectKey, forHTTPHeaderField: Header.authorization.rawValue)
        request.addValue(device.appVersion ?? "", forHTTPHeaderField: Header.appVersion.rawValue)
        request.addValue(device.country ?? "", forHTTPHeaderField: Header.country.rawValue)
        request.addValue(device.language ?? "", forHTTPHeaderField: Header.userLocale.rawValue)
        request.addValue(UserDefaults.source, forHTTPHeaderField: Header.source.rawValue)
        request.addValue(sdkVersion, forHTTPHeaderField: Header.sourceVersion.rawValue)
        request.addValue(device.osName, forHTTPHeaderField: Header.platform.rawValue)
        request.addValue(device.osVersion, forHTTPHeaderField: Header.platformVersion.rawValue)
    }
}

#endif
