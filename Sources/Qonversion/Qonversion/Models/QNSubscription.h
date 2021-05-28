//
//  QNSubscription.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QNSubscriptionRenewState){
  QNSubscriptionRenewStateUnknown = -1,
  QNSubscriptionRenewStateWillRenew = 1,
  QNSubscriptionRenewStateCanceled = 2,
  QNSubscriptionRenewStateBillingIssue = 3
} NS_SWIFT_NAME(Qonversion.SubscriptionRenewState);

typedef NS_ENUM(NSInteger, QNSubscriptionPeriodType){
  QNSubscriptionPeriodTypeUnknown = -1,
  QNSubscriptionPeriodTypeNormal = 1,
  QNSubscriptionPeriodTypeTrial = 2,
  QNSubscriptionPeriodTypeIntro = 3
} NS_SWIFT_NAME(Qonversion.SubscriptionPeriodType);

@interface QNSubscription : NSObject

@property (nonatomic, copy, readonly) NSString *periodDuration;
@property (nonatomic, strong, readonly) NSDate *startDate;
@property (nonatomic, strong, readonly) NSDate *currentPeriodStartDate;
@property (nonatomic, strong, readonly) NSDate *currentPeriodEndDate;
@property (nonatomic, copy, readonly) NSString *currentPeriodTypeRawValue;
@property (nonatomic, assign, readonly) QNSubscriptionPeriodType currentPeriodType;
@property (nonatomic, assign, readonly) QNSubscriptionRenewState renewState;
@property (nonatomic, copy, readonly) NSString *object;

@end

NS_ASSUME_NONNULL_END
