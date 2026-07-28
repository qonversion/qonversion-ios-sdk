//
//  Device.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import Foundation

/// The device record, in the exact shape both sides of the contract implement.
/// The endpoint echoes the object back, so one key set serves encoding and
/// decoding; the decode is tolerant because a truncated echo must not cost the
/// SDK the record it just created.
struct Device: Equatable, Codable {

    let osName: String
    let osVersion: String
    let model: String?
    let appVersion: String?
    let country: String?
    let language: String?
    let advertisingId: String?
    let vendorId: String?
    /// Unix seconds on the wire.
    let installDate: TimeInterval

    enum CodingKeys: String, CodingKey {
        case osName = "os_name"
        case osVersion = "os_version"
        case model
        case appVersion = "app_version"
        case country
        case language
        case advertisingId = "advertising_id"
        case vendorId = "vendor_id"
        case installDate = "install_date"
    }

    init(
        osName: String,
        osVersion: String,
        model: String?,
        appVersion: String?,
        country: String?,
        language: String?,
        advertisingId: String?,
        vendorId: String?,
        installDate: TimeInterval
    ) {
        self.osName = osName
        self.osVersion = osVersion
        self.model = model
        self.appVersion = appVersion
        self.country = country
        self.language = language
        self.advertisingId = advertisingId
        self.vendorId = vendorId
        self.installDate = installDate
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.osName = try container.decodeIfPresent(String.self, forKey: .osName) ?? ""
        self.osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion) ?? ""
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        self.country = try container.decodeIfPresent(String.self, forKey: .country)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.advertisingId = try container.decodeIfPresent(String.self, forKey: .advertisingId)
        self.vendorId = try container.decodeIfPresent(String.self, forKey: .vendorId)
        self.installDate = try container.decodeIfPresent(TimeInterval.self, forKey: .installDate) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(osName, forKey: .osName)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(advertisingId, forKey: .advertisingId)
        try container.encodeIfPresent(vendorId, forKey: .vendorId)
        // An interval that is not representable as seconds falls through to the
        // Double encoding, which reports the failure instead of trapping.
        if let seconds: Int = Int(exactly: installDate.rounded(.down)) {
            try container.encode(seconds, forKey: .installDate)
        } else {
            try container.encode(installDate, forKey: .installDate)
        }
    }
}
