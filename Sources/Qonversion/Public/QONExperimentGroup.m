//
//  QONExperimentGroup.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONExperimentGroup.h"

@implementation QONExperimentGroup

- (instancetype)initWithType:(QONExperimentGroupType)type name:(NSString *)name {
  self = [super init];
  
  if (self) {
    _type = type;
    _name = name;
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _type = [coder decodeIntForKey:NSStringFromSelector(@selector(type))];
    _name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeInteger:_type forKey:NSStringFromSelector(@selector(type))];
  [coder encodeObject:_name forKey:NSStringFromSelector(@selector(name))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendFormat:@"name=%@\n", self.name];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyType {
  NSString *result;
  
  switch (self.type) {
    case QONExperimentGroupTypeTreatment:
      result = @"B"; break;
      
    default:
      result = @"A";
      break;
  }
  
  return result;
}

@end
