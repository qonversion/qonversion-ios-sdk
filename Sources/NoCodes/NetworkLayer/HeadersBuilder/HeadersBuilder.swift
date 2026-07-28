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

// @unchecked: the collector is Sendable; UserDefaults is thread-safe.
final class HeadersBuilder: HeadersBuilderInterface, @unchecked Sendable {

    let projectKey: String
    let sdkVersion: String
    let deviceInfoCollector: DeviceInfoCollectorInterface
    let userDefaults: UserDefaults

    init(projectKey: String, sdkVersion: String, deviceInfoCollector: DeviceInfoCollectorInterface, userDefaults: UserDefaults) {
        self.projectKey = projectKey
        self.sdkVersion = sdkVersion
        self.deviceInfoCollector = deviceInfoCollector
        self.userDefaults = userDefaults
    }

    func addHeaders(to request: inout URLRequest) {
        let device: Device = deviceInfoCollector.deviceInfo()

        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: Header.contentType.rawValue)
        request.addValue("Bearer " + projectKey, forHTTPHeaderField: Header.authorization.rawValue)
        request.addValue(device.appVersion ?? "", forHTTPHeaderField: Header.appVersion.rawValue)
        request.addValue(device.country ?? "", forHTTPHeaderField: Header.country.rawValue)
        request.addValue(device.language ?? "", forHTTPHeaderField: Header.userLocale.rawValue)

        let resolved: (source: String, sourceVersion: String) = resolvedSource()
        request.addValue(resolved.source, forHTTPHeaderField: Header.source.rawValue)
        request.addValue(resolved.sourceVersion, forHTTPHeaderField: Header.sourceVersion.rawValue)
        request.addValue(device.osName, forHTTPHeaderField: Header.platform.rawValue)
        request.addValue(device.osVersion, forHTTPHeaderField: Header.platformVersion.rawValue)
    }

    // Wrappers set BOTH keys. The production Objective-C SDK also persisted its
    // own version into the version key, so on an upgraded install a version
    // override without a source override is a leftover, not a wrapper.
    private func resolvedSource() -> (source: String, sourceVersion: String) {
        guard let sourceOverride: String = userDefaults.string(forKey: SourceOverrideKeys.source.rawValue) else {
            return ("iOS", sdkVersion)
        }

        let versionOverride: String? = userDefaults.string(forKey: SourceOverrideKeys.sourceVersion.rawValue)

        return (sourceOverride, versionOverride ?? sdkVersion)
    }
}
