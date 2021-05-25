//
//  QNSubscription+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNSubscription.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNSubscription (Protected)

- (instancetype)initWithObject:(NSString *)object
                periodDuration:(NSString *)periodDuration
                     startDate:(NSDate *)startDate
        currentPeriodStartDate:(NSDate *)currentPeriodStartDate
          currentPeriodEndDate:(NSDate *)currentPeriodEndDate
     currentPeriodTypeRawValue:(NSString *)currentPeriodTypeRawValue
             currentPeriodType:(QNSubscriptionPeriodType)currentPeriodType
                    renewState:(QNSubscriptionRenewState)renewState;

@end

NS_ASSUME_NONNULL_END
