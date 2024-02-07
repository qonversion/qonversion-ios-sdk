//
//  DeviceInfoCollector.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
#if canImport(AdSupport)
import AdSupport
#endif
#if os(macOS)
import IOKit
#elseif os(watchOS)
import WatchKit
#endif

protocol DeviceInfoCollectorInterface {
  func getDeviceInfo() -> Device
}

#if os(macOS)
  private let OsName = "macOS";
#elseif os(tvOS)
  private let OsName = "tvos";
#elseif targetEnvironment(macCatalyst)
  private let OsName = "macCatalyst";
#elseif os(watchOS)
  private let OsName = "watchOS";
#else // iOS, simulator, etc.
  private let OsName = "iOS"
#endif

public class DeviceInfoCollector: DeviceInfoCollectorInterface {
  
  var lastPreparedDevice: Device? = nil
  
  func getDeviceInfo() -> Device {
    guard let deviceInfo = lastPreparedDevice else {
      let manufacturer = "Apple"
      let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String  ?? ""
      let osVersion = getOsVersion()
      let model = getDeviceModel()
      let installDate = getInstallDate()
      let country = getCountry()
      let language = getLanguage()
      let timezone = TimeZone.current.identifier
      let advertisingId = getAdvertisingId()
      let vendorId = getVendorId()

      let deviceInfo = Device(
        manufacturer: manufacturer,
        osName: OsName,
        osVersion: osVersion,
        model: model,
        appVersion: appVersion,
        country: country,
        language: language,
        timezone: timezone,
        advertisingId: advertisingId,
        vendorID: vendorId,
        installDate: installDate
      )

      lastPreparedDevice = deviceInfo
      return deviceInfo
    }
  
    return deviceInfo
  }
  
  private func getOsVersion() -> String {
    var osVersion = ""
    
#if os(iOS)
    osVersion = UIDevice.current.systemVersion
#elseif os(watchOS)
    osVersion = WKInterfaceDevice.current().systemVersion
#else
    let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
    osVersion = "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
#endif
    
    return osVersion
  }
  
  private func getDeviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let modelCode = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            ptr in String.init(validatingUTF8: ptr)
        }
    }
    return modelCode ?? ""
  }
  
  private func getInstallDate() -> String {
    let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    if let docsURL = docsURL {
        if let docsAttributes = try? FileManager.default.attributesOfItem(atPath: docsURL.path) {
            if let date = docsAttributes[.creationDate] as? Date {
                let installDate = "\(Int(round(date.timeIntervalSince1970)))"
                return installDate
            }
        }
    }
    
    return ""
  }

  private func getCountry() -> String {
    let country = NSLocale(localeIdentifier: "en_US").displayName(forKey: .countryCode, value: Locale.current.regionCode ?? "")
    
    return country ?? ""
  }
  
  private func getLanguage() -> String {
    let language = NSLocale(localeIdentifier: "en_US").displayName(forKey: .languageCode, value: NSLocale.preferredLanguages[0])

    return language ?? "";
  }
  
  private func getAdvertisingId() -> String {
    var result = ""

#if canImport(AdSupport)
    let advertisingId = ASIdentifierManager.shared().advertisingIdentifier
    result = advertisingId.uuidString
      
    if result == "00000000-0000-0000-0000-000000000000" {
      result = ""
    }
#endif

    return result
  }

  private func getVendorId() -> String {
    var identifier: String? = nil
#if os(iOS)
    identifier = UIDevice.current.identifierForVendor?.uuidString;
#elseif os(watchOS)
    identifier = WKInterfaceDevice.current().identifierForVendor?.uuidString
#elseif os(macOS)
    identifier = getMacAddress()
#endif
    
    return identifier ?? ""
  }

#if os(macOS)
  private func getMacAddress(_ name: String = "en0") -> String? {
    var iterator = io_iterator_t()
    defer {
      if iterator != IO_OBJECT_NULL {
        IOObjectRelease(iterator)
      }
    }

      guard let matchingDict = IOBSDNameMatching(kIOMainPortDefault, 0, name),
            IOServiceGetMatchingServices(kIOMainPortDefault,
            matchingDict as CFDictionary,
            &iterator) == KERN_SUCCESS,
          iterator != IO_OBJECT_NULL
    else {
      return nil
    }

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
