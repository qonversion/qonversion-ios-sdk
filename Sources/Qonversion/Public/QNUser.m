//
//  QNUser.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUser.h"

@implementation QNUser

- (instancetype)initWithID:(NSString *)identifier
              entitlements:(NSArray<QNEntitlement *> *)entitlements
                 purchases:(NSArray<QNPurchase *> *)purchases
                    object:(NSString *)object
                createDate:(NSDate *)createDate
            lastOnlineDate:(NSDate *)lastOnlineDate
        originalAppVersion:(NSString *)originalAppVersion {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _entitlements = entitlements;
    _purchases = purchases;
    _object = object;
    _createDate = createDate;
    _lastOnlineDate = lastOnlineDate;
    _originalAppVersion = originalAppVersion;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"identifier=%@,\n", self.identifier];
  [description appendFormat:@"entitlements=%@,\n", self.entitlements];
  [description appendFormat:@"purchases=%@,\n", self.purchases];
  [description appendFormat:@"object=%@", self.object];
  [description appendFormat:@"createDate=%@", self.createDate];
  [description appendFormat:@"lastOnlineDate=%@", self.lastOnlineDate];
  [description appendFormat:@"originalAppVersion=%@", self.originalAppVersion];
  [description appendString:@">"];
  
  return [description copy];
}

@end
