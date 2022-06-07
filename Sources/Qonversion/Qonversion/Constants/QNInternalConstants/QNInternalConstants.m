//
//  QNInternalConstants.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNInternalConstants.h"

NSString *const kKeyQKeyChainUserID = @"Qonversion.Keeper.userID";
NSString *const kKeyQUserDefaultsIdentityUserID = @"com.qonversion.keys.identityUserID";
NSString *const kKeyQUserDefaultsUserID = @"com.qonversion.keys.storedUserID";
NSString *const kKeyQUserDefaultsPermissions = @"com.qonversion.keys.permissions";
NSString *const kKeyQUserDefaultsPermissionsTimestamp = @"com.qonversion.keys.permissions.timestamp";
NSString *const kKeyQUserIDPrefix = @"QON";
NSString *const kKeyQUserIDSeparator = @"_";
NSString *const kMainUserDefaultsSuiteName = @"qonversion.localstorage.main";

NSString *const kKeyQExperimentStartedEventName = @"offering_within_experiment_called";

NSUInteger const kQPropertiesSendingPeriodInSeconds = 5;
CGFloat const kJitter = 0.4f;
CGFloat const kFactor = 2.4f;
NSUInteger const kMaxDelay = 1000;
NSUInteger const kNotFoundErrorCode = 404;
