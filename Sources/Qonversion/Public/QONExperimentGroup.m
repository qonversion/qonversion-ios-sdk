//
//  QONExperimentGroup.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONExperimentGroup.h"

@implementation QONExperimentGroup

- (instancetype)initWithIdentifier:(NSString *)identifier type:(QONExperimentGroupType)type name:(NSString *)name {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _type = type;
    _name = name;
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _identifier = [coder decodeObjectForKey:NSStringFromSelector(@selector(identifier))];
    _type = [coder decodeIntForKey:NSStringFromSelector(@selector(type))];
    _name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_identifier forKey:NSStringFromSelector(@selector(identifier))];
  [coder encodeInteger:_type forKey:NSStringFromSelector(@selector(type))];
  [coder encodeObject:_name forKey:NSStringFromSelector(@selector(name))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  [description appendFormat:@"identifier=%@\n", self.identifier];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendFormat:@"name=%@\n", self.name];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyType {
  NSString *result;
  
  switch (self.type) {
    case QONExperimentGroupTypeControl:
      result = @"control"; break;
    case QONExperimentGroupTypeTreatment:
      result = @"treatment"; break;
      
    default:
      result = @"unknown"; break;
  }
  
  return result;
}

@end
