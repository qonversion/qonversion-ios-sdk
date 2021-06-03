//
//  QNInternalConstants.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 18.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNInternalConstants.h"

NSString *const kKeyQKeyChainUserID = @"Qonversion.Keeper.userID";
NSString *const kKeyQUserDefaultsOriginalUserID = @"com.qonversion.keys.originalUserID";
NSString *const kKeyQUserDefaultsUserID = @"com.qonversion.keys.storedUserID";
NSString *const kKeyQUserIDPrefix = @"QON";
NSString *const kKeyQUserIDSeparator = @"_";
NSString *const kMainUserDefaultsSuiteName = @"qonversion.localstorage.main";

NSUInteger const kQPropertiesSendingPeriodInSeconds = 5;
CGFloat const kJitter = 0.4f;
CGFloat const kFactor = 2.4f;
NSUInteger const kMaxDelay = 1000;
