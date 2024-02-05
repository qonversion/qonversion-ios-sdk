//
//  DeviceInfoCollector.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation
import CoreTelephony
import AdSupport

protocol DeviceInfoCollectorInterface {
  func getDeviceInfo() -> Device
}

private let OsName = "iOS"

public class DeviceInfoCollector: DeviceInfoCollectorInterface {
  
  let lastPreparedDevice: Device? = nil
  
  func getDeviceInfo() -> Device {
    guard let deviceInfo = lastPreparedDevice else {
      let manufacturer = "Apple"
      let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String  ?? ""
      let osVersion = getOsVersion()
      let model = getDeviceModel()
      let installDate = getInstallDate()
      let carrier = getCarrier()
      let country = getCountry()
      let language = getLanguage()
      let timezone = TimeZone.current.identifier
      let advertisingId = getAdvertisingId()
      let vendorId = getVendorId()
      
      return Device(
        manufacturer: manufacturer,
        osName: OsName,
        osVersion: osVersion,
        model: model,
        appVersion: appVersion,
        carrier: carrier,
        country: country,
        language: language,
        timezone: timezone,
        advertisingId: advertisingId,
        vendorID: vendorId,
        installDate: installDate
      )
    }
  
    return deviceInfo
  }
  
  private func getOsVersion() -> String {
    var osVersion = ""
    
#if UI_DEVICE
    osVersion = UIDevice.current.systemVersion
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
  
  private func getCarrier() -> String {
    var carrierName: String? = nil

    let networkInfo = CTTelephonyNetworkInfo()
    if let carrier = networkInfo.subscriberCellularProvider {
      carrierName = carrier.carrierName
    }

    return carrierName ?? "Unknown"
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
    let advertisingId = ASIdentifierManager.shared().advertisingIdentifier
    
    let uuid = advertisingId.uuidString
    if uuid == "00000000-0000-0000-0000-000000000000" {
      return ""
    }

    return uuid
  }

  private func getVendorId() -> String {
    UIDevice.current.identifierForVendor?.uuidString ?? "";
  }
}
