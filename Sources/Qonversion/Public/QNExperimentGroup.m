//
//  QNExperimentGroup.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNExperimentGroup.h"

@implementation QNExperimentGroup

- (instancetype)initWithType:(QNExperimentGroupType)type {
  self = [super init];
  
  if (self) {
    _type = type;
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _type = [coder decodeIntForKey:NSStringFromSelector(@selector(type))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeInteger:_type forKey:NSStringFromSelector(@selector(type))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyType {
  NSString *result;
  
  switch (self.type) {
    case QNExperimentGroupTypeB:
      result = @"B"; break;
      
    default:
      result = @"A";
      break;
  }
  
  return result;
}

@end
