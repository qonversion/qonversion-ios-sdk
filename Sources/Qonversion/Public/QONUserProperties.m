//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import "QONUserProperties.h"
#import "QONUserProperty.h"


@implementation QONUserProperties : NSObject

- (instancetype)initWithProperties:(NSArray<QONUserProperty *> *)properties {
  self = [super init];

  if (self) {
    _properties = [properties copy];
    [self initCollections];
  }

  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];

  if (self) {
    _properties = [coder decodeObjectForKey:NSStringFromSelector(@selector(properties))];
    [self initCollections];
  }

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_properties forKey:NSStringFromSelector(@selector(properties))];
}

- (void)initCollections {
  NSMutableArray<QONUserProperty *> *definedPropertiesList = [NSMutableArray array];
  for (QONUserProperty *userProperty in _properties) {
    if (userProperty.definedKey != QONUserPropertyKeyCustom) {
      [definedPropertiesList addObject:userProperty];
    }
  }
  _definedProperties = [definedPropertiesList copy];

  NSMutableArray<QONUserProperty *> *customPropertiesList = [NSMutableArray array];
  for (QONUserProperty *userProperty in _properties) {
    if (userProperty.definedKey == QONUserPropertyKeyCustom) {
      [customPropertiesList addObject:userProperty];
    }
  }
  _customProperties = [customPropertiesList copy];

  NSMutableDictionary<NSString *, NSString *> *propertiesMap = [NSMutableDictionary dictionary];
  for (QONUserProperty *userProperty in _properties) {
    propertiesMap[userProperty.key] = userProperty.value;
  }
  _flatPropertiesMap = [propertiesMap copy];

  NSMutableDictionary<NSNumber *, NSString *> *definedPropertiesMap = [NSMutableDictionary dictionary];
  for (QONUserProperty *userProperty in _definedProperties) {
    definedPropertiesMap[@(userProperty.definedKey)] = userProperty.value;
  }
  _flatDefinedPropertiesMap = [definedPropertiesMap copy];

  NSMutableDictionary<NSString *, NSString *> *customPropertiesMap = [NSMutableDictionary dictionary];
  for (QONUserProperty *userProperty in _customProperties) {
    customPropertiesMap[userProperty.key] = userProperty.value;
  }
  _flatCustomPropertiesMap = [customPropertiesMap copy];
}

- (nullable QONUserProperty *)propertyForKey:(NSString *)key {
  for (QONUserProperty *userProperty in _properties) {
    if ([userProperty.key isEqualToString:key]) {
      return userProperty;
    }
  }

  return nil;
}

- (nullable QONUserProperty *)definedPropertyForKey:(QONUserPropertyKey)key {
  for (QONUserProperty *userProperty in _definedProperties) {
    if (userProperty.definedKey == key) {
      return userProperty;
    }
  }

  return nil;
}

@end
