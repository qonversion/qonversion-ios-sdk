//
//  Device.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

class Device {
  let manufacturer: String
  let osName: String
  let osVersion: String
  let model: String
  let appVersion: String
  let carrier: String
  let country: String
  let language: String
  let timezone: String
  let advertisingId: String
  let vendorID: String
  let installDate: String

  init(
    manufacturer: String,
    osName: String,
    osVersion: String,
    model: String,
    appVersion: String,
    carrier: String,
    country: String,
    language: String,
    timezone: String,
    advertisingId: String,
    vendorID: String,
    installDate: String
  ) {
    self.manufacturer = manufacturer
    self.osName = osName
    self.osVersion = osVersion
    self.model = model
    self.appVersion = appVersion
    self.carrier = carrier
    self.country = country
    self.language = language
    self.timezone = timezone
    self.advertisingId = advertisingId
    self.vendorID = vendorID
    self.installDate = installDate
  }
}
