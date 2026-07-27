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
class HeadersBuilder: HeadersBuilderInterface, @unchecked Sendable {

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
        // The cheap header slice only — the full device snapshot (IDFA, IDFV,
        // model) belongs to the device update flow, not to every request.
        let device: HeaderDeviceInfo = deviceInfoCollector.headerDeviceInfo()

        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: Header.contentType.rawValue)
        request.addValue("Bearer " + apiKey, forHTTPHeaderField: Header.authorization.rawValue)
        addNonEmpty(device.appVersion, header: .appVersion, to: &request)
        addNonEmpty(device.country, header: .country, to: &request)
        addNonEmpty(device.language, header: .userLocale, to: &request)
        let (source, sourceVersion) = resolvedSource()
        request.addValue(source, forHTTPHeaderField: Header.source.rawValue)
        request.addValue(sourceVersion, forHTTPHeaderField: Header.sourceVersion.rawValue)
        request.addValue(device.osName, forHTTPHeaderField: Header.platform.rawValue)
        request.addValue(device.osVersion, forHTTPHeaderField: Header.platformVersion.rawValue)
    }

    /// Cross-platform wrappers set BOTH override keys. The production
    /// Objective-C SDK also persisted its own version into the source-version
    /// key, so on installs upgraded from it a version override without a
    /// source override is a leftover, not a wrapper — it must be ignored or
    /// the backend would see the old native version forever.
    private func resolvedSource() -> (source: String, sourceVersion: String) {
        guard let sourceOverride: String = userDefaults.string(forKey: SourceOverrideKeys.source.rawValue) else {
            return ("iOS", sdkVersion)
        }

        let versionOverride: String? = userDefaults.string(forKey: SourceOverrideKeys.sourceVersion.rawValue)
        return (sourceOverride, versionOverride ?? sdkVersion)
    }

    /// Production omits empty header values; an empty string and an absent
    /// header are different signals to the backend.
    private func addNonEmpty(_ value: String?, header: Header, to request: inout URLRequest) {
        guard let value, !value.isEmpty else { return }

        request.addValue(value, forHTTPHeaderField: header.rawValue)
    }
}
