//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONUserProperty.h"

@class QONUserProperty;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.UserProperties)
@interface QONUserProperties : NSObject <NSCoding>

@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *properties;
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *definedProperties;
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *customProperties;
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSString *, NSString*> *propertiesMap;
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSNumber *, NSString*> *definedPropertiesMap;
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSString *, NSString*> *customPropertiesMap;

- (nullable QONUserProperty *)propertyForKey:(nonnull NSString *)key
NS_SWIFT_NAME(property(for:));

- (nullable QONUserProperty *)definedPropertyForKey:(QONUserPropertyKey)key
NS_SWIFT_NAME(definedProperty(for:));

@end

NS_ASSUME_NONNULL_END
