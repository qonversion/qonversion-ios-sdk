//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import "QONUserPropertiesMapper.h"
#import "QONUserProperty.h"
#import "QONUserProperty+Protected.h"
#import "QONUserProperties+Protected.h"


@implementation QONUserPropertiesMapper

- (QONUserProperties *_Nullable)mapUserProperties:(NSArray *)userPropertiesData {
  if (![userPropertiesData isKindOfClass:[NSArray class]]) {
    return nil;
  }

  NSMutableArray<QONUserProperty *> *properties = [NSMutableArray new];
  for (NSDictionary *userPropertyData in userPropertiesData) {
    QONUserProperty *property = [self mapUserProperty:userPropertyData];
    if (property != nil) {
      [properties addObject:property];
    }
  }

  return [[QONUserProperties alloc] initWithProperties:properties];
}

- (QONUserProperty *_Nullable)mapUserProperty:(NSDictionary *)userPropertyData {
  if (![userPropertyData isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  NSString *key = userPropertyData[@"key"];
  NSString *value = userPropertyData[@"value"];

  if (!key || !value) {
    return nil;
  }

  return [[QONUserProperty alloc] initWithKey:key value:value];
}

@end