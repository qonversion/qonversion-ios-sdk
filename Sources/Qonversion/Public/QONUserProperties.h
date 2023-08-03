//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONUserProperty.h"

@class QONUserProperty;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.UserProperties)
@interface QONUserProperties : NSObject

/**
 List of all user properties.
 */
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *properties;

/**
 List of user properties, set for the Qonversion defined keys.
 This is a subset of all `properties` list.
 @see `Qonversion.setUserProperty`
 */
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *definedProperties;

/**
 List of user properties, set for custom keys.
 This is a subset of all `properties` list.
 @see `Qonversion.setCustomUserProperty`
 */
@property (nonatomic, copy, nonnull, readonly) NSArray<QONUserProperty *> *customProperties;

/**
 Map of all user properties.
 This is a flattened version of the `properties` list as a key-value map.
 */
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSString *, NSString*> *flatPropertiesMap;

/**
 Map of user properties, set for the Qonversion defined keys.
 This is a flattened version of the `definedProperties` list as a key-value map, where keys are values from `QONUserPropertyKey`.
 @see `Qonversion.setUserProperty`
 */
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSNumber *, NSString*> *flatDefinedPropertiesMap;

/**
 Map of user properties, set for custom keys.
 This is a flattened version of the `customProperties` list as a key-value map.
 @see `Qonversion.setCustomUserProperty`
 */
@property (nonatomic, copy, nonnull, readonly) NSDictionary<NSString *, NSString*> *flatCustomPropertiesMap;

- (nullable QONUserProperty *)propertyForKey:(nonnull NSString *)key
NS_SWIFT_NAME(property(for:));

- (nullable QONUserProperty *)definedPropertyForKey:(QONUserPropertyKey)key
NS_SWIFT_NAME(definedProperty(for:));

@end

NS_ASSUME_NONNULL_END
