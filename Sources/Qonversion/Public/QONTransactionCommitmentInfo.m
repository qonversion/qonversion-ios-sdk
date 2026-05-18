//
//  QONTransactionCommitmentInfo.m
//  Qonversion
//
//  Created by Qonversion on 2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONTransactionCommitmentInfo.h"

@implementation QONTransactionCommitmentInfo

- (instancetype)initWithBillingPeriodNumber:(NSUInteger)billingPeriodNumber
                        totalBillingPeriods:(NSUInteger)totalBillingPeriods
                      pricePerBillingPeriod:(NSDecimalNumber *)pricePerBillingPeriod
          currentBillingPeriodExpirationDate:(NSDate *)currentBillingPeriodExpirationDate {
  self = [super init];

  if (self) {
    _billingPeriodNumber = billingPeriodNumber;
    _totalBillingPeriods = totalBillingPeriods;
    _pricePerBillingPeriod = pricePerBillingPeriod;
    _currentBillingPeriodExpirationDate = currentBillingPeriodExpirationDate;
  }

  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _billingPeriodNumber = [coder decodeIntegerForKey:NSStringFromSelector(@selector(billingPeriodNumber))];
    _totalBillingPeriods = [coder decodeIntegerForKey:NSStringFromSelector(@selector(totalBillingPeriods))];
    _pricePerBillingPeriod = [coder decodeObjectForKey:NSStringFromSelector(@selector(pricePerBillingPeriod))];
    _currentBillingPeriodExpirationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(currentBillingPeriodExpirationDate))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeInteger:_billingPeriodNumber forKey:NSStringFromSelector(@selector(billingPeriodNumber))];
  [coder encodeInteger:_totalBillingPeriods forKey:NSStringFromSelector(@selector(totalBillingPeriods))];
  [coder encodeObject:_pricePerBillingPeriod forKey:NSStringFromSelector(@selector(pricePerBillingPeriod))];
  [coder encodeObject:_currentBillingPeriodExpirationDate forKey:NSStringFromSelector(@selector(currentBillingPeriodExpirationDate))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  [description appendFormat:@"billingPeriodNumber=%lu,\n", (unsigned long)self.billingPeriodNumber];
  [description appendFormat:@"totalBillingPeriods=%lu,\n", (unsigned long)self.totalBillingPeriods];
  [description appendFormat:@"pricePerBillingPeriod=%@,\n", self.pricePerBillingPeriod];
  [description appendFormat:@"currentBillingPeriodExpirationDate=%@\n", self.currentBillingPeriodExpirationDate];
  [description appendString:@">"];
  return [description copy];
}

@end
