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
    _definedKey = [QNProperties propertyForKey:_key];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _key = [coder decodeObjectForKey:NSStringFromSelector(@selector(key))];
    _value = [coder decodeObjectForKey:NSStringFromSelector(@selector(value))];
    _definedKey = [QNProperties propertyForKey:_key];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_key forKey:NSStringFromSelector(@selector(key))];
  [coder encodeObject:_value forKey:NSStringFromSelector(@selector(value))];
}

@end