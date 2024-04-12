//
//  Device.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

extension Qonversion {
    
    struct Device: Comparable, Codable {
        
        let manufacturer: String
        let osName: String
        let osVersion: String
        let model: String?
        let appVersion: String?
        let country: String?
        let language: String?
        let timezone: String?
        let advertisingId: String?
        let vendorId: String?
        let installDate: TimeInterval

        init(
            manufacturer: String,
            osName: String,
            osVersion: String,
            model: String?,
            appVersion: String?,
            country: String?,
            language: String?,
            timezone: String,
            advertisingId: String?,
            vendorId: String?,
            installDate: TimeInterval
        ) {
            self.manufacturer = manufacturer
            self.osName = osName
            self.osVersion = osVersion
            self.model = model
            self.appVersion = appVersion
            self.country = country
            self.language = language
            self.timezone = timezone
            self.advertisingId = advertisingId
            self.vendorId = vendorId
            self.installDate = installDate
        }
        
        static func < (lhs: Device, rhs: Device) -> Bool {
            let isEqual: Bool = lhs.manufacturer == rhs.manufacturer
            && lhs.osName == rhs.osName
            && lhs.osVersion == rhs.osVersion
            && lhs.model == rhs.model
            && lhs.appVersion == rhs.appVersion
            && lhs.country == rhs.country
            && lhs.language == rhs.language
            && lhs.timezone == rhs.timezone
            && lhs.advertisingId == rhs.advertisingId
            && lhs.vendorId == rhs.vendorId
            && lhs.installDate == rhs.installDate
            
            return isEqual
        }
    }
    
}
