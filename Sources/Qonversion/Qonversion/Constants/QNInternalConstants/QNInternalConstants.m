//
//  QNInternalConstants.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNInternalConstants.h"

NSString *const keyQInternalUserID = @"keyQInternalUserID";
NSString *const keyQONUserPropertyKeyReg = @"(?=.*[a-zA-Z])^[-a-zA-Z0-9_.:]+$";
NSString *const keyQSource = @"com.qonversion.keys.source";
NSString *const keyQSourceVersion = @"com.qonversion.keys.sourceVersion";

NSString *const kHistoricalDataSynced = @"isHistoricalDataSynced";

#if TARGET_OS_OSX
    NSString *const kQNPlatform = @"macOS";
    NSString *const kQNOSName = @"macos";
#elif TARGET_OS_TV
    NSString *const kQNPlatform = @"tvOS";
    NSString *const kQNOSName = @"tvos";
#elif TARGET_OS_MACCATALYST
    NSString *const kQNPlatform = @"macCatalyst";
    NSString *const kQNOSName = @"macCatalyst";
#elif TARGET_OS_WATCH
    NSString *const kQNPlatform = @"watchOS";
    NSString *const kQNOSName = @"watchOS";
#else // iOS, simulator, etc.
    NSString *const kQNPlatform = @"iOS";
    NSString *const kQNOSName = @"ios";
#endif

NSString *const kKeyQKeyChainUserID = @"Qonversion.Keeper.userID";
NSString *const kKeyQUserDefaultsOriginalUserID = @"com.qonversion.keys.originalUserID";
NSString *const kKeyQUserDefaultsIdentityUserID = @"com.qonversion.keys.identityUserID";
NSString *const kKeyQUserDefaultsUserID = @"com.qonversion.keys.storedUserID";
NSString *const kKeyQUserIDPrefix = @"QON";
NSString *const kKeyQUserIDSeparator = @"_";
NSString *const kKeyQUserDefaultsPermissions = @"com.qonversion.keys.entitlements";
NSString *const kKeyQPermissionsTransfered = @"com.qonversion.keys.entitlements.transfered";
NSString *const kKeyQUserDefaultsPermissionsTimestamp = @"com.qonversion.keys.permissions.timestamp";
NSString *const kKeyQUserDefaultsProductsPermissionsRelation = @"com.qonversion.keys.products.permissions.relation";
NSString *const kMainUserDefaultsSuiteName = @"qonversion.localstorage.main";
NSString *const kKeyQUserDefaultsStoredPurchasesRequests = @"com.qonversion.keys.requests.stored.purchases";

NSString *const kKeyQExperimentStartedEventName = @"offering_within_experiment_called";

NSString *const kKeyNotificationsCustomPayload = @"qonv.custom_payload";

NSUInteger const kQPropertiesSendingPeriodInSeconds = 5;
CGFloat const kJitter = 0.4f;
CGFloat const kFactor = 2.4f;
NSUInteger const kMaxDelay = 1000;

NSInteger const kInternalServerErrorFirstCode = 500;
NSInteger const kInternalServerErrorLastCode = 599;

NSString *const kLaunchIsFinishedNotification = @"qonv.notifications.launch.finished";
