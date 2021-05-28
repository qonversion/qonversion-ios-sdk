//
//  QNUserProduct.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNUserProduct.h"

@implementation QNUserProduct

- (instancetype)initWithIdentifier:(NSString *)identifier
                              type:(QNUserProductType)type
                          currency:(NSString *)currency
                             price:(NSInteger)price
                 introductoryPrice:(NSInteger)introductoryPrice
              introductoryDuration:(NSString *)introductoryDuration
                      subscription:(QNSubscription *)subscription
                            object:(NSString *)object {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _type = type;
    _currency = currency;
    _price = price;
    _introductoryPrice = introductoryPrice;
    _introductoryDuration = introductoryDuration;
    _subscription = subscription;
    _object = object;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"identifier=%@,\n", self.identifier];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long)self.type];
  [description appendFormat:@"currency=%@", self.currency];
  [description appendFormat:@"price=%ld", (long)self.price];
  [description appendFormat:@"introductoryPrice=%ld", (long)self.introductoryPrice];
  [description appendFormat:@"introductoryDuration=%@", self.introductoryDuration];
  [description appendFormat:@"subscription=%@", self.subscription];
  [description appendFormat:@"object=%@", self.object];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyType {
  NSString *result = @"unknown";
  
  switch (self.type) {
    case QNUserProductTypeSubscription:
      result = @"Subscription"; break;
    
    case QNUserProductTypeNonRecurring:
      result = @"Non recurring"; break;
    
    default:
      break;
  }
  
  return result;
}

@end
