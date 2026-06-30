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
                            commitmentPrice:(NSDecimalNumber *)commitmentPrice
                   commitmentExpirationDate:(NSDate *)commitmentExpirationDate {
  self = [super init];

  if (self) {
    _billingPeriodNumber = billingPeriodNumber;
    _totalBillingPeriods = totalBillingPeriods;
    _commitmentPrice = commitmentPrice;
    _commitmentExpirationDate = commitmentExpirationDate;
  }

  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _billingPeriodNumber = [coder decodeIntegerForKey:NSStringFromSelector(@selector(billingPeriodNumber))];
    _totalBillingPeriods = [coder decodeIntegerForKey:NSStringFromSelector(@selector(totalBillingPeriods))];
    _commitmentPrice = [coder decodeObjectForKey:NSStringFromSelector(@selector(commitmentPrice))];
    _commitmentExpirationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(commitmentExpirationDate))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeInteger:_billingPeriodNumber forKey:NSStringFromSelector(@selector(billingPeriodNumber))];
  [coder encodeInteger:_totalBillingPeriods forKey:NSStringFromSelector(@selector(totalBillingPeriods))];
  [coder encodeObject:_commitmentPrice forKey:NSStringFromSelector(@selector(commitmentPrice))];
  [coder encodeObject:_commitmentExpirationDate forKey:NSStringFromSelector(@selector(commitmentExpirationDate))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  [description appendFormat:@"billingPeriodNumber=%lu,\n", (unsigned long)self.billingPeriodNumber];
  [description appendFormat:@"totalBillingPeriods=%lu,\n", (unsigned long)self.totalBillingPeriods];
  [description appendFormat:@"commitmentPrice=%@,\n", self.commitmentPrice];
  [description appendFormat:@"commitmentExpirationDate=%@\n", self.commitmentExpirationDate];
  [description appendString:@">"];
  return [description copy];
}

@end
