//
//  UserPropertyKey.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

/**
 Qonversion Defined User Property keys
 We defined some common case properties and provided API for adding them
 */
public enum UserPropertyKey: String {
    case email = "_q_email"
    case name = "_q_name"
    case appsFlyerUserId = "_q_appsflyer_user_id"
    case adjustAdId = "_q_adjust_adid"
    case kochavaDeviceId = "_q_kochava_device_id"
    case advertisingId = "_q_advertising_id"
    case userId = "_q_custom_user_id"
    case firebaseAppInstanceId = "_q_firebase_instance_id"
    case facebookAttribution = "_q_fb_attribution" // Android only can be received via Qonversion.userProperties
    case appSetId = "_q_app_set_id" // Android only can be received via Qonversion.userProperties
    case pushWooshUserId = "_q_pushwoosh_user_id"
    case pushWooshHwId = "_q_pushwoosh_hwid"
    case appMetricaDeviceId = "_q_appmetrica_device_id"
    case appMetricaUserProfileId = "_q_appmetrica_user_profile_id"
    case custom = ""
}
