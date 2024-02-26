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
enum UserPropertyKey {
  case email
  case name
  case appsFlyerUserID
  case adjustAdID
  case kochavaDeviceID
  case advertisingID
  case userID
  case firebaseAppInstanceId
  case facebookAttribution // Android only can be received via Qonversion.userProperties
  case appSetId // Android only can be received via Qonversion.userProperties
  case pushWooshUserId
  case pushWooshHwId
  case appMetricaDeviceId
  case appMetricaUserProfileId
  case custom;
  
  func key() -> String? {
      var key: String?
      switch self {
      case .email:
          key = "_q_email"
      case .name:
          key = "_q_name"
      case .kochavaDeviceID:
          key = "_q_kochava_device_id"
      case .appsFlyerUserID:
          key = "_q_appsflyer_user_id"
      case .adjustAdID:
          key = "_q_adjust_adid"
      case .advertisingID:
          key = "_q_advertising_id"
      case .userID:
          key = "_q_custom_user_id"
      case .firebaseAppInstanceId:
          key = "_q_firebase_instance_id"
      case .facebookAttribution:
          key = "_q_fb_attribution"
      case .appSetId:
          key = "_q_app_set_id"
      case .pushWooshUserId:
          key = "_q_pushwoosh_user_id"
      case .pushWooshHwId:
          key = "_q_pushwoosh_hwid"
      case .appMetricaDeviceId:
          key = "_q_appmetrica_device_id"
      case .appMetricaUserProfileId:
          key = "_q_appmetrica_user_profile_id"
      case .custom:
          key = nil
      }
      
      return key
  }

  static func from(key: String) -> UserPropertyKey {
      let propertiesMap: [String: UserPropertyKey] = [
          "_q_email": .email,
          "_q_name": .name,
          "_q_kochava_device_id": .kochavaDeviceID,
          "_q_appsflyer_user_id": .appsFlyerUserID,
          "_q_adjust_adid": .adjustAdID,
          "_q_advertising_id": .advertisingID,
          "_q_custom_user_id": .userID,
          "_q_firebase_instance_id": .firebaseAppInstanceId,
          "_q_fb_attribution": .facebookAttribution,
          "_q_app_set_id": .appSetId,
          "_q_pushwoosh_user_id": .pushWooshUserId,
          "_q_pushwoosh_hwid": .pushWooshHwId,
          "_q_appmetrica_device_id": .appMetricaDeviceId,
          "_q_appmetrica_user_profile_id": .appMetricaUserProfileId
      ]
      
      return propertiesMap[key] ?? .custom
  }
}
