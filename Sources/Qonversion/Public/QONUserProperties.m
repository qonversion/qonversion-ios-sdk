//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import "QONUserProperties.h"

@implementation QONUserProperties : NSObject

- (instancetype)initWithProperties:(NSArray<QONUserProperty *> *)properties {
  self = [super init];

  if (self) {
    _properties = [properties copy];
    [self initCollections];
  }

  return self;
}

- (void)initCollections {
  NSMutableArray<QONUserProperty *> *definedPropertiesList = [NSMutableArray new];
  NSMutableArray<QONUserProperty *> *customPropertiesList = [NSMutableArray new];
  NSMutableDictionary<NSString *, NSString *> *propertiesMap = [NSMutableDictionary new];
  NSMutableDictionary<NSNumber *, NSString *> *definedPropertiesMap = [NSMutableDictionary new];
  NSMutableDictionary<NSString *, NSString *> *customPropertiesMap = [NSMutableDictionary new];

  for (QONUserProperty *userProperty in _properties) {
    propertiesMap[userProperty.key] = userProperty.value;

    if (userProperty.definedKey == QONUserPropertyKeyCustom) {
      [customPropertiesList addObject:userProperty];
      customPropertiesMap[userProperty.key] = userProperty.value;
    } else {
      [definedPropertiesList addObject:userProperty];
      definedPropertiesMap[@(userProperty.definedKey)] = userProperty.value;
    }
  }

  _definedProperties = [definedPropertiesList copy];
  _customProperties = [customPropertiesList copy];
  _flatPropertiesMap = [propertiesMap copy];
  _flatDefinedPropertiesMap = [definedPropertiesMap copy];
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
