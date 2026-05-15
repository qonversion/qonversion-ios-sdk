//
//  QONTransactionCommitmentInfo.h
//  Qonversion
//
//  Created by Qonversion on 2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commitment information for a subscription with a fixed-term billing commitment
 (e.g. a monthly subscription with a 12-month commitment).
 Maps to Transaction.CommitmentInfo (iOS 26.4+).
 */
NS_SWIFT_NAME(Qonversion.TransactionCommitmentInfo)
@interface QONTransactionCommitmentInfo : NSObject <NSCoding>

/**
 The current billing period number within the commitment (1-based).
 For example, 4 means the user is in their 4th billing period.
 */
@property (nonatomic, assign) NSUInteger billingPeriodNumber;

/**
 The total number of billing periods in the commitment.
 For example, 12 for a 12-month commitment.
 */
@property (nonatomic, assign) NSUInteger totalBillingPeriods;

/**
 The price charged per billing period.
 */
@property (nonatomic, strong, nonnull) NSDecimalNumber *pricePerBillingPeriod;

/**
 The expiration date of the current billing period.
 */
@property (nonatomic, strong, nonnull) NSDate *currentBillingPeriodExpirationDate;

- (instancetype)initWithBillingPeriodNumber:(NSUInteger)billingPeriodNumber
                        totalBillingPeriods:(NSUInteger)totalBillingPeriods
                       pricePerBillingPeriod:(NSDecimalNumber *)pricePerBillingPeriod
      currentBillingPeriodExpirationDate:(NSDate *)currentBillingPeriodExpirationDate
NS_SWIFT_NAME(init(billingPeriodNumber:totalBillingPeriods:pricePerBillingPeriod:currentBillingPeriodExpirationDate:));

@end

NS_ASSUME_NONNULL_END
