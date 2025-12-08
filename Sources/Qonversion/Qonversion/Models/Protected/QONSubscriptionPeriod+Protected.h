//
//  QONSubscriptionPeriod+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.11.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QONSubscriptionPeriod ()

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (instancetype)initWithStoreSubscriptionPeriod:(SKProductSubscriptionPeriod *)subscriptionPeriod;
#pragma clang diagnostic pop

@end

NS_ASSUME_NONNULL_END
