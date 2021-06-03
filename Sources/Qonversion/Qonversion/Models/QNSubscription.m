//
//  QNSubscription.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNSubscription.h"

@implementation QNSubscription

- (instancetype)initWithObject:(NSString *)object
                periodDuration:(NSString *)periodDuration
                     startDate:(NSDate *)startDate
        currentPeriodStartDate:(NSDate *)currentPeriodStartDate
          currentPeriodEndDate:(NSDate *)currentPeriodEndDate
     currentPeriodTypeRawValue:(NSString *)currentPeriodTypeRawValue
             currentPeriodType:(QNSubscriptionPeriodType)currentPeriodType
                    renewState:(QNSubscriptionRenewState)renewState {
  self = [super init];
  
  if (self) {
    _object = object;
    _periodDuration = periodDuration;
    _startDate = startDate;
    _currentPeriodStartDate = currentPeriodStartDate;
    _currentPeriodEndDate = currentPeriodEndDate;
    _currentPeriodTypeRawValue = currentPeriodTypeRawValue;
    _currentPeriodType = currentPeriodType;
    _renewState = renewState;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"object=%@", self.object];
  [description appendFormat:@"periodDuration=%@,\n", self.periodDuration];
  [description appendFormat:@"startDate=%@", self.startDate];
  [description appendFormat:@"currentPeriodStartDate=%@", self.currentPeriodStartDate];
  [description appendFormat:@"currentPeriodEndDate=%@", self.currentPeriodEndDate];
  [description appendFormat:@"currentPeriodTypeRawValue=%@", self.currentPeriodTypeRawValue];
  [description appendFormat:@"currentPeriodType=%@ (enum value = %li),\n", [self prettyCurrentPeriodType], (long)self.currentPeriodType];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyRenewState], (long)self.renewState];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyRenewState {
  NSString *result = @"unknown";
  
  switch (self.renewState) {
    case QNSubscriptionRenewStateWillRenew:
      result = @"Will renew"; break;
    
    case QNSubscriptionRenewStateCanceled:
      result = @"Canceled"; break;
      
    case QNSubscriptionRenewStateBillingIssue:
      result = @"Billing issue"; break;
    
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettyCurrentPeriodType {
  NSString *result = @"unknown";
  
  switch (self.currentPeriodType) {
    case QNSubscriptionPeriodTypeIntro:
      result = @"Intro"; break;
    
    case QNSubscriptionPeriodTypeTrial:
      result = @"Trial"; break;
      
    case QNSubscriptionPeriodTypeNormal:
      result = @"Normal"; break;
    
    default:
      break;
  }
  
  return result;
}

@end
