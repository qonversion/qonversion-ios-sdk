//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONUserProperties, QONUserProperty;

NS_ASSUME_NONNULL_BEGIN

@interface QONUserPropertiesMapper : NSObject

- (QONUserProperties * _Nullable)mapUserProperties:(NSArray *)userPropertiesData;
- (QONUserProperty * _Nullable)mapUserProperty:(NSDictionary *)userPropertyData;

@end

NS_ASSUME_NONNULL_END