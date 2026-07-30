//
//  DeviceInfoCollector.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import IOKit
#elseif os(watchOS)
import WatchKit
#endif

// The platform the SDK reports to the backend. Consistent casing across all
// of them, and visionOS is its own platform — it used to report as iOS.
// macCatalyst is checked before macOS: a Catalyst build matches both.
#if targetEnvironment(macCatalyst)
private let OsName = "macCatalyst"
#elseif os(macOS)
private let OsName = "macOS"
#elseif os(tvOS)
private let OsName = "tvOS"
#elseif os(watchOS)
private let OsName = "watchOS"
#elseif os(visionOS)
private let OsName = "visionOS"
#else // iOS, simulator, etc.
private let OsName = "iOS"
#endif

final class DeviceInfoCollector: DeviceInfoCollectorInterface {

    /// The moment this install first appeared on the device. Injectable so the
    /// normalisation rules can be tested without a file system of a given age.
    typealias InstallDateProvider = @Sendable () -> Date

    private let advertisingIdReader: AdvertisingIdReader
    private let installDateProvider: InstallDateProvider
    private let vendorIdResolver: VendorIdResolver

    init(
        userDefaults: UserDefaults = .standard,
        installDateProvider: @escaping InstallDateProvider = DeviceInfoCollector.documentsCreationDate
    ) {
        let advertisingIdReader = AdvertisingIdReader()
        self.advertisingIdReader = advertisingIdReader
        self.installDateProvider = installDateProvider
        self.vendorIdResolver = VendorIdResolver(userDefaults: userDefaults)
    }

    func deviceInfo() -> Device {
        // Built fresh on every call: advertisingId (ATT grant), locale and
        // appVersion change at runtime, and a cached snapshot would keep the
        // device update diff empty forever.
        let appVersion: String? = Bundle.appVersion
        let osVersion: String = osVersion()
        let model: String? = deviceModel()
        let installDate: TimeInterval = installDate()
        let country: String? = country()
        let language: String? = language()
        let advertisingId: String? = advertisingId()
        let vendorId: String? = vendorId()

        let deviceInfo = Device(
            osName: OsName,
            osVersion: osVersion,
            model: model,
            appVersion: appVersion,
            country: country,
            language: language,
            advertisingId: advertisingId,
            vendorId: vendorId,
            installDate: installDate
        )

        return deviceInfo
    }
    
    func headerDeviceInfo() -> HeaderDeviceInfo {
        let headerDeviceInfo = HeaderDeviceInfo(
            appVersion: Bundle.appVersion,
            country: country(),
            language: language(),
            osName: OsName,
            osVersion: osVersion()
        )

        return headerDeviceInfo
    }

    /// Nil unless the host app links Apple's advertising framework itself and
    /// the user authorised tracking — see `AdvertisingIdReader` for why the SDK
    /// never links it.
    func advertisingId() -> String? {
        return advertisingIdReader.advertisingId()
    }

    private func osVersion() -> String {
        var osVersion: String? = nil

        #if os(iOS)
        osVersion = UIDevice.current.systemVersion
        #elseif os(watchOS)
        osVersion = WKInterfaceDevice.current().systemVersion
        #else
        let systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
        #endif

        return osVersion ?? ""
    }

    private func deviceModel() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode: String? = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        return modelCode
    }

    @Sendable
    static func documentsCreationDate() -> Date {
        if let docsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let docsAttributes: [FileAttributeKey : Any] = try? FileManager.default.attributesOfItem(atPath: docsURL.path),
           let date = docsAttributes[.creationDate] as? Date {
            return date
        }

        return Date()
    }

    /// Whole seconds: the wire and the local snapshot both carry the install
    /// date as an integer, so a fractional value would never compare equal to
    /// the record it was stored as.
    private func installDate() -> TimeInterval {
        return installDateProvider().timeIntervalSince1970.rounded(.down)
    }

    private func country() -> String? {
        return if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
            Locale.current.region?.identifier
        } else {
            Locale.current.regionCode
        }
    }

    private func language() -> String? {
        return if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
            Locale.current.language.languageCode?.identifier
        } else {
            Locale.current.languageCode
        }
    }

    private func vendorId() -> String {
        var identifier: String? = nil
        #if os(iOS) || os(tvOS) || os(visionOS)
        identifier = UIDevice.current.identifierForVendor?.uuidString
        #elseif os(watchOS)
        identifier = WKInterfaceDevice.current().identifierForVendor?.uuidString
        #elseif os(macOS)
        identifier = getMacAddress()
        #endif

        return vendorIdResolver.resolve(systemVendorId: identifier)
    }

    #if os(macOS)
    private func getMacAddress(_ name: String = "en0") -> String? {
        var iterator = io_iterator_t()
        defer {
            if iterator != IO_OBJECT_NULL {
                IOObjectRelease(iterator)
            }
        }

        var port: mach_port_t
        if #available(macOS 12.0, *) {
            port = kIOMainPortDefault
        } else {
            port = kIOMasterPortDefault
        }
        guard let matchingDict = IOBSDNameMatching(port, 0, name),
              IOServiceGetMatchingServices(port, matchingDict as CFDictionary, &iterator) == KERN_SUCCESS,
              iterator != IO_OBJECT_NULL
        else { return nil }

        var candidate = IOIteratorNext(iterator)
        while candidate != IO_OBJECT_NULL {
            if let cftype = IORegistryEntryCreateCFProperty(candidate, "IOBuiltin" as CFString, kCFAllocatorDefault, 0) {
                // swiftlint:disable:next force_cast
                let isBuiltIn = cftype.takeRetainedValue() as! CFBoolean
                if CFBooleanGetValue(isBuiltIn) {
                    let property = IORegistryEntrySearchCFProperty(
                        candidate,
                        kIOServicePlane,
                        "IOMACAddress" as CFString,
                        kCFAllocatorDefault,
                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
                    ) as? Data
                    IOObjectRelease(candidate)
                    return property?.map { String(format: "%02X", $0) }.joined(separator: ":")
                }
            }

            IOObjectRelease(candidate)
            candidate = IOIteratorNext(iterator)
        }

        return nil
    }
    #endif
}
