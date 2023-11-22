//
//  QNInternalConstants.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#if TARGET_OS_OSX
#define DID_ENTER_BACKGROUND_NOTIFICATION_NAME NSApplicationDidResignActiveNotification
#elif TARGET_OS_IOS || TARGET_OS_TV
#define DID_ENTER_BACKGROUND_NOTIFICATION_NAME UIApplicationDidEnterBackgroundNotification
#elif TARGET_OS_WATCH
#define DID_ENTER_BACKGROUND_NOTIFICATION_NAME NSExtensionHostDidEnterBackgroundNotification
#endif

#if TARGET_OS_IOS || TARGET_OS_TV
#define UI_DEVICE 1
#else
#define UI_DEVICE 0
#endif

extern NSString *const keyQInternalUserID;
extern NSString *const keyQONUserPropertyKeyReg;
extern NSString *const keyQSource;
extern NSString *const keyQSourceVersion;

extern NSString *const kQNPlatform;
extern NSString *const kQNOSName;

extern NSString *const kHistoricalDataSynced;

extern NSString *const kKeyQKeyChainUserID;
extern NSString *const kKeyQUserDefaultsIdentityUserID;
extern NSString *const kKeyQUserDefaultsOriginalUserID;
extern NSString *const kKeyQUserDefaultsUserID;
extern NSString *const kKeyQUserIDPrefix;
extern NSString *const kKeyQUserIDSeparator;
extern NSString *const kKeyQUserDefaultsPermissions;
extern NSString *const kKeyQPermissionsTransfered;
extern NSString *const kKeyQUserDefaultsPermissionsTimestamp;
extern NSString *const kKeyQUserDefaultsProductsPermissionsRelation;
extern NSString *const kMainUserDefaultsSuiteName;
extern NSString *const kKeyQUserDefaultsStoredPurchasesRequests;
extern NSString *const kKeyQExperimentStartedEventName;
extern NSString *const kKeyNotificationsCustomPayload;
extern NSUInteger const kQPropertiesSendingPeriodInSeconds;
extern CGFloat const kJitter;
extern CGFloat const kFactor;
extern NSUInteger const kMaxDelay;
extern NSInteger const kInternalServerErrorFirstCode;
extern NSInteger const kInternalServerErrorLastCode;

extern NSString *const kLaunchIsFinishedNotification;
