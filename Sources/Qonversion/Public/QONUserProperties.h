//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

@class QONUserProperty;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.UserProperties)
@interface QONUserProperties : NSObject <NSCoding>

@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *propertiesList;
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *definedPropertiesList;
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *customPropertiesList;
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSString *, NSString*> *propertiesMap;
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSNumber *, NSString*> *definedPropertiesMap;
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSString *, NSString*> *customPropertiesMap;

- (nullable QONUserProperty *)propertyForKey:(nonnull NSString *)key
NS_SWIFT_NAME(property(for:));

- (nullable QONUserProperty *)definedPropertyForKey:(QONUserPropertyKey)key
NS_SWIFT_NAME(definedProperty(for:));

- (nullable QONUserProperty *)customPropertyForKey:(nonnull NSString *)key
NS_SWIFT_NAME(customProperty(for:));

@end

NS_ASSUME_NONNULL_END
