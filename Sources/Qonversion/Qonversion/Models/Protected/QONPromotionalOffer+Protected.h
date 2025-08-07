//
//  QONPromotionalOffer+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONPromotionalOffer.h"
#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QONPromotionalOffer (Protected)

- (instancetype)initWithProductDiscount:(SKProductDiscount *)productDiscount paymentDiscount:(SKPaymentDiscount *)paymentDiscount;

@end

NS_ASSUME_NONNULL_END
