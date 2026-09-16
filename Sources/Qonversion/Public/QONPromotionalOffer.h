//
//  QONPromotionalOffer.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.PromotionalOffer)
API_AVAILABLE(ios(12.2), macos(10.14.4), watchos(6.2), tvos(12.2), visionos(1.0))
@interface QONPromotionalOffer : NSObject

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@property (nonatomic, strong) SKProductDiscount *productDiscount;
@property (nonatomic, strong) SKPaymentDiscount *paymentDiscount;

/**
 Creates a promotional offer from the StoreKit discount and the signed payment discount.
 @param productDiscount discount of the product the offer is applied to.
 @param paymentDiscount signed payment discount obtained from Qonversion (see `-[Qonversion getPromotionalOffer:discount:completion:]`).
 */
- (instancetype)initWithProductDiscount:(SKProductDiscount *)productDiscount paymentDiscount:(SKPaymentDiscount *)paymentDiscount;
#pragma clang diagnostic pop

@end

NS_ASSUME_NONNULL_END
