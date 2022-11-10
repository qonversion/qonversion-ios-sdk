//
//  QONUser.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONUser.h"

@implementation QONUser

- (instancetype)initWithID:(NSString *)identifier
        originalAppVersion:(NSString *)originalAppVersion {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _originalAppVersion = originalAppVersion;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"identifier=%@,\n", self.identifier];
  [description appendFormat:@"originalAppVersion=%@", self.originalAppVersion];
  [description appendString:@">"];
  
  return [description copy];
}

@end
