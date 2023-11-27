//
//  QONSubscriptionPeriod.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.11.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONSubscriptionPeriod.h"
#import <StoreKit/StoreKit.h>

@implementation QONSubscriptionPeriod

- (instancetype)initWithStoreSubscriptionPeriod:(SKProductSubscriptionPeriod *)subscriptionPeriod {
  self = [super init];
  
  if (self) {
    _unit = [self convertStoreUnit:subscriptionPeriod.unit];
    _unitCount = subscriptionPeriod.numberOfUnits;
  }
  
  return self;
}

- (QONSubscriptionPeriodUnit)convertStoreUnit:(SKProductPeriodUnit)unit {
  switch (unit) {
    case SKProductPeriodUnitDay:
      return QONSubscriptionPeriodUnitDay;
      break;
    
    case SKProductPeriodUnitWeek:
      return QONSubscriptionPeriodUnitWeek;
      break;
      
    case SKProductPeriodUnitMonth:
      return QONSubscriptionPeriodUnitMonth;
      break;
      
    case SKProductPeriodUnitYear:
      return QONSubscriptionPeriodUnitYear;
      break;
  }
}

+ (NSString *)unitStringFormat:(QONSubscriptionPeriodUnit)unit {
  switch (unit) {
    case QONSubscriptionPeriodUnitDay:
      return @"day";
      break;
      
    case QONSubscriptionPeriodUnitWeek:
      return @"week";
      break;
      
    case QONSubscriptionPeriodUnitMonth:
      return @"month";
      break;
      
    case QONSubscriptionPeriodUnitYear:
      return @"year";
      break;
      
    default:
      break;
  }
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"unit=%@,\n", [QONSubscriptionPeriod unitStringFormat:self.unit]];
  [description appendFormat:@"count= %li \n", (long) self.unitCount];
  [description appendString:@">"];
  
  return [description copy];
}

@end
