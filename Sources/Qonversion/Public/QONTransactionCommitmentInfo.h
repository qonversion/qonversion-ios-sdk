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
 The total price of the whole commitment (for example, the full 12-month amount),
 in the transaction's currency. This is the commitment total, not a single billing period.
 */
@property (nonatomic, strong, nonnull) NSDecimalNumber *commitmentPrice;

/**
 The date the whole commitment expires (the end of the final billing period),
 not the expiration of the current billing period.
 */
@property (nonatomic, strong, nonnull) NSDate *commitmentExpirationDate;

- (instancetype)initWithBillingPeriodNumber:(NSUInteger)billingPeriodNumber
                        totalBillingPeriods:(NSUInteger)totalBillingPeriods
                            commitmentPrice:(NSDecimalNumber *)commitmentPrice
                   commitmentExpirationDate:(NSDate *)commitmentExpirationDate
NS_SWIFT_NAME(init(billingPeriodNumber:totalBillingPeriods:commitmentPrice:commitmentExpirationDate:));

@end

NS_ASSUME_NONNULL_END
