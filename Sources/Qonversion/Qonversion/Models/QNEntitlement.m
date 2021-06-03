//
//  QNEntitlement.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNEntitlement.h"

@implementation QNEntitlement

- (instancetype)initWithID:(NSString *)entitlementID
                    userID:(NSString *)userID
                    active:(BOOL)active
               startedDate:(NSDate *)startedDate
            expirationDate:(NSDate *)expirationDate
                 purchases:(NSArray<QNPurchase *> *)purchases
                    object:(NSString *)object {
  self = [super init];
  
  if (self) {
    _entitlementID = entitlementID;
    _userID = userID;
    _active = active;
    _startedDate = startedDate;
    _expirationDate = expirationDate;
    _purchases = purchases;
    _object = object;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"entitlementID=%@,\n", self.entitlementID];
  [description appendFormat:@"userID=%@,\n", self.userID];
  [description appendFormat:@"active=%@,\n", self.active ? @"true" : @"false"];
  [description appendFormat:@"startedDate=%@", self.startedDate];
  [description appendFormat:@"expirationDate=%@", self.expirationDate];
  [description appendFormat:@"purchases=%@", self.purchases];
  [description appendFormat:@"object=%@", self.object];
  [description appendString:@">"];
  
  return [description copy];
}

@end
