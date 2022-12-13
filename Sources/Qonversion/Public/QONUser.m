//
//  QONUser.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONUser.h"

@implementation QONUser

- (instancetype)initWithID:(NSString *)qonversionId
        originalAppVersion:(NSString *)originalAppVersion
                identityId:(NSString *_Nullable)identityId {
  self = [super init];
  
  if (self) {
    _qonversionId = qonversionId;
    _originalAppVersion = originalAppVersion;
    _identityId = identityId;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"qonversionId=%@,\n", self.qonversionId];
  [description appendFormat:@"identityId=%@,\n", self.identityId];
  [description appendFormat:@"originalAppVersion=%@", self.originalAppVersion];
  [description appendString:@">"];
  
  return [description copy];
}

@end
