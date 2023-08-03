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
    _propertiesList = [properties copy];
    [self initCollections];
  }

  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];

  if (self) {
    _propertiesList = [coder decodeObjectForKey:NSStringFromSelector(@selector(properties))];
    [self initCollections];
  }

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_propertiesList forKey:NSStringFromSelector(@selector(properties))];
}

- (void)initCollections {
  NSMutableArray<QONUserProperty *> *definedPropertiesList = [NSMutableArray array];
  for (QONUserProperty *userProperty in _propertiesList) {
    if (userProperty.definedKey != QONUserPropertyKeyCustom) {
      [definedPropertiesList addObject:userProperty];
    }
  }
  _definedPropertiesList = [definedPropertiesList copy];

  NSMutableArray<QONUserProperty *> *customPropertiesList = [NSMutableArray array];
  for (QONUserProperty *userProperty in _propertiesList) {
    if (userProperty.definedKey == QONUserPropertyKeyCustom) {
      [customPropertiesList addObject:userProperty];
    }
  }
  _customPropertiesList = [customPropertiesList copy];

  NSMutableDictionary<NSString *, NSString *> *propertiesMap = [NSMutableDictionary dictionary];
  for (QONUserProperty *userProperty in _propertiesList) {
    propertiesMap[userProperty.key] = userProperty.value;
  }
  _propertiesMap = [propertiesMap copy];

  NSMutableDictionary<NSNumber *, NSString *> *definedPropertiesMap = [NSMutableDictionary dictionary];
  for (QONUserProperty *userProperty in _definedPropertiesList) {
    definedPropertiesMap[@(userProperty.definedKey)] = userProperty.value;
  }
  _definedPropertiesMap = [definedPropertiesMap copy];

  NSMutableDictionary<NSString *, NSString *> *customPropertiesMap = [NSMutableDictionary dictionary];
  for (QONUserProperty *userProperty in _customPropertiesList) {
    customPropertiesMap[userProperty.key] = userProperty.value;
  }
  _customPropertiesMap = [customPropertiesMap copy];
}

- (nullable QONUserProperty *)propertyForKey:(NSString *)key {
  for (QONUserProperty *userProperty in _propertiesList) {
    if ([userProperty.key isEqualToString:key]) {
      return userProperty;
    }
  }

  return nil;
}

- (nullable QONUserProperty *)definedPropertyForKey:(QONUserPropertyKey)key {
  for (QONUserProperty *userProperty in _definedPropertiesList) {
    if (userProperty.definedKey == key) {
      return userProperty;
    }
  }

  return nil;
}

@end
