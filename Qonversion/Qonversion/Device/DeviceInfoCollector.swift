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

#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit
#elseif os(watchOS)
import WatchKit
#endif

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

final class DeviceInfoCollector: DeviceInfoCollectorInterface {

  var lastPreparedDevice: Device? = nil

  func deviceInfo() -> Device {
    if let savedDevice = lastPreparedDevice {
      return savedDevice
    }

    let manufacturer = "Apple"
    let appVersion: String? = Bundle.appVersion
    let osVersion: String? = osVersion()
    let model: String? = deviceModel()
    let installDate: TimeInterval = installDate()
    let country: String? = country()
    let language: String? = language()
    let timezone: String = TimeZone.current.identifier
    let advertisingId: String? = advertisingId()
    let vendorId: String? = vendorId()

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

  private func osVersion() -> String? {
    var osVersion: String? = nil

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

  private func installDate() -> TimeInterval {
    if let docsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
       let docsAttributes: [FileAttributeKey : Any] = try? FileManager.default.attributesOfItem(atPath: docsURL.path),
       let date = docsAttributes[.creationDate] as? Date {
      return date.timeIntervalSince1970
    }

    return Date().timeIntervalSince1970
  }

  private func country() -> String? {
    return if #available(iOS 16, *) {
      Locale.current.region?.identifier
    } else {
      Locale.current.regionCode
    }
  }

  private func language() -> String? {
    return if #available(iOS 16, *) {
      Locale.current.language.languageCode?.identifier
    } else {
      Locale.current.languageCode
    };
  }

  private func advertisingId() -> String? {
    var result: String? = nil

#if canImport(AdSupport)
    let advertisingId: UUID = ASIdentifierManager.shared().advertisingIdentifier
    result = advertisingId.uuidString

    if result == "00000000-0000-0000-0000-000000000000" {
      result = ""
    }
#endif

    return result
  }

  private func vendorId() -> String? {
    var identifier: String? = nil
#if os(iOS)
    identifier = UIDevice.current.identifierForVendor?.uuidString;
#elseif os(watchOS)
    identifier = WKInterfaceDevice.current().identifierForVendor?.uuidString
#elseif os(macOS)
    identifier = getMacAddress()
#endif

    return identifier
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
          IOServiceGetMatchingServices(port,
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
