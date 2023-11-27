//
//  QONSubscriptionPeriod.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.11.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONSubscriptionPeriodUnit) {
  QONSubscriptionPeriodUnitDay = 0,
  QONSubscriptionPeriodUnitWeek = 1,
  QONSubscriptionPeriodUnitMonth = 2,
  QONSubscriptionPeriodUnitYear = 3
} NS_SWIFT_NAME(Qonversion.SubscriptionPeriodUnit);

API_AVAILABLE(ios(11.2), macosx(10.13.2), watchos(6.2), tvos(11.2))
NS_SWIFT_NAME(Qonversion.SubscriptionPeriod)
@interface QONSubscriptionPeriod : NSObject

@property (nonatomic, assign) QONSubscriptionPeriodUnit unit;

@property (nonatomic, assign) NSUInteger unitCount;

+ (NSString *)unitStringFormat:(QONSubscriptionPeriodUnit)unit;

@end

NS_ASSUME_NONNULL_END
