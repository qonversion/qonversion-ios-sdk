//
//  UserPropertyKey.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 23.02.2024.
//

import Foundation

extension Qonversion {
    
    /// Qonversion Defined User Property keys.
    ///
    /// We've defined some common case properties and provided API for adding them
    public enum UserPropertyKey: String {
        
        /// Email
        case email = "_q_email"
        
        /// Name
        case name = "_q_name"
        
        /// AppsFlyer user ID
        case appsFlyerUserId = "_q_appsflyer_user_id"
        
        /// Adjust advertising ID
        case adjustAdId = "_q_adjust_adid"
        
        /// Kochava device ID
        case kochavaDeviceId = "_q_kochava_device_id"
        
        /// Advertising ID
        case advertisingId = "_q_advertising_id"
        
        /// User ID
        case userId = "_q_custom_user_id"
        
        /// Firebase app instance ID
        case firebaseAppInstanceId = "_q_firebase_instance_id"
        
        /// Facebook attribution
        case facebookAttribution = "_q_fb_attribution" // Android only can be received via Qonversion.userProperties
        
        /// App set id
        case appSetId = "_q_app_set_id" // Android only can be received via Qonversion.userProperties
        
        /// Pushwoosh user ID
        case pushWooshUserId = "_q_pushwoosh_user_id"
        
        /// Pushwoosh HW ID
        case pushWooshHwId = "_q_pushwoosh_hwid"
        
        /// AppMetrica device ID
        case appMetricaDeviceId = "_q_appmetrica_device_id"
        
        /// AppMetrica user profile ID
        case appMetricaUserProfileId = "_q_appmetrica_user_profile_id"
        
        /// Value for custom user property
        /// - Important: Do not pass this value directly. Use ``Qonversion/Qonversion/setCustomUserProperty(_:key:)`` instead.
        case custom = ""
        
    }
    
}
