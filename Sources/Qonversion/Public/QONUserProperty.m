//
// Created by Kamo Spertsyan on 31.07.2023.
// Copyright (c) 2023 Qonversion Inc. All rights reserved.
//

#import "QONUserProperty.h"
#import "QNProperties.h"

@implementation QONUserProperty : NSObject

- (instancetype)initWithKey:(NSString *)key value:(NSString *)value {
  self = [super init];
  if (self) {
    _key = key;
    _value = value;
    _definedKey = [QNProperties propertyKeyFromString:key];
  }
  return self;
}

@end