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

- (instancetype)initWithStoreSubscriptionPeriod:(SKProductSubscriptionPeriod *)subscriptionPeriod;

@end

NS_ASSUME_NONNULL_END
