//
//  QNExperimentInfo.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNExperimentInfo.h"

@implementation QNExperimentInfo

- (instancetype)initWithIdentifier:(NSString *)identifier group:(QNExperimentGroup * _Nullable)group {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _group = group;
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _identifier = [coder decodeObjectForKey:NSStringFromSelector(@selector(identifier))];
    _group = [coder decodeObjectForKey:NSStringFromSelector(@selector(group))];
    _attached = [coder decodeBoolForKey:NSStringFromSelector(@selector(attached))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_identifier forKey:NSStringFromSelector(@selector(identifier))];
  [coder encodeObject:_group forKey:NSStringFromSelector(@selector(group))];
  [coder encodeBool:_attached forKey:NSStringFromSelector(@selector(attached))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.identifier];
  [description appendFormat:@"group=%@\n", self.group];
  [description appendFormat:@"accepted=%d\n", self.attached];
  [description appendString:@">"];
  
  return [description copy];
}

@end
