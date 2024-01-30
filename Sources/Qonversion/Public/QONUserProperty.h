//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Qonversion Defined User Property keys
 We defined some common case properties and provided API for adding them
 */
typedef NS_ENUM(NSInteger, QONUserPropertyKey) {
    QONUserPropertyKeyEmail = 0,
    QONUserPropertyKeyName,
    QONUserPropertyKeyAppsFlyerUserID,
    QONUserPropertyKeyAdjustAdID,
    QONUserPropertyKeyKochavaDeviceID,
    QONUserPropertyKeyAdvertisingID,
    QONUserPropertyKeyUserID,
    QONUserPropertyKeyFirebaseAppInstanceId,
    QONUserPropertyKeyFacebookAttribution, // Android only, can be received via Qonversion.userProperties
    QONUserPropertyKeyAppSetId, // Android only, can be received via Qonversion.userProperties
    QONUserPropertyKeyPushWooshUserId,
    QONUserPropertyKeyPushWooshHwId,
    QONUserPropertyKeyAppMetricaDeviceId,
    QONUserPropertyKeyAppMetricaUserProfileId,
    QONUserPropertyKeyCustom,
} NS_SWIFT_NAME(Qonversion.UserPropertyKey);

NS_SWIFT_NAME(Qonversion.UserProperty)
@interface QONUserProperty : NSObject

/**
 Raw property key
 */
@property (nonatomic, copy, readonly) NSString *key;

/**
 Property value
 */
@property (nonatomic, copy, readonly) NSString *value;

/**
 Qonversion defined property key. `Custom` for non-Qonversion properties.
 */
@property (nonatomic, assign, readonly) QONUserPropertyKey definedKey;

@end

NS_ASSUME_NONNULL_END
