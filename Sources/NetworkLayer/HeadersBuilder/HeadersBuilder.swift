//
//  HeadersBuilder.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 07.02.2024.
//

import Foundation

fileprivate enum SourceOverrideKeys: String {
    // Set by cross-platform wrappers (React Native, Flutter, etc.) so the
    // backend can distinguish them from the native SDK.
    case source = "com.qonversion.keys.source"
    case sourceVersion = "com.qonversion.keys.sourceVersion"
}

class HeadersBuilder: HeadersBuilderInterface {
    
    let apiKey: String
    let sdkVersion: String
    let deviceInfoCollector: DeviceInfoCollectorInterface
    let userDefaults: UserDefaults
    
    init(apiKey: String, sdkVersion: String, deviceInfoCollector: DeviceInfoCollectorInterface, userDefaults: UserDefaults) {
        self.apiKey = apiKey
        self.sdkVersion = sdkVersion
        self.deviceInfoCollector = deviceInfoCollector
        self.userDefaults = userDefaults
    }
    
    func addHeaders(to request: inout URLRequest) {
        let device: Device = deviceInfoCollector.deviceInfo()
        
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: Header.contentType.rawValue)
        request.addValue("Bearer " + apiKey, forHTTPHeaderField: Header.authorization.rawValue)
        request.addValue(device.appVersion ?? "", forHTTPHeaderField: Header.appVersion.rawValue)
        request.addValue(device.country ?? "", forHTTPHeaderField: Header.country.rawValue)
        request.addValue(device.language ?? "", forHTTPHeaderField: Header.userLocale.rawValue)
        let source: String = userDefaults.string(forKey: SourceOverrideKeys.source.rawValue) ?? "iOS"
        request.addValue(source, forHTTPHeaderField: Header.source.rawValue)
        let sourceVersion: String = userDefaults.string(forKey: SourceOverrideKeys.sourceVersion.rawValue) ?? sdkVersion
        request.addValue(sourceVersion, forHTTPHeaderField: Header.sourceVersion.rawValue)
        request.addValue(device.osName, forHTTPHeaderField: Header.platform.rawValue)
        request.addValue(device.osVersion, forHTTPHeaderField: Header.platformVersion.rawValue)
    }
}
