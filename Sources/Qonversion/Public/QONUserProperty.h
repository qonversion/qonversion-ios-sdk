//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.UserProperty)
@interface QONUserProperty : NSObject <NSCoding>

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
@property (nonatomic, readonly) QONUserPropertyKey definedKey;

@end

NS_ASSUME_NONNULL_END
