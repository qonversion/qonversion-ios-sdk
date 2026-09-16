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
 Creates a promotional offer to pass through `QONPurchaseOptions.promoOffer` (StoreKit 1 purchase flow).
 Prefer `-[Qonversion getPromotionalOfferForProduct:discount:completion:]`, which builds and signs the offer for you;
 use this initializer when the payment discount is signed by your own server.
 @param productDiscount discount of the `SKProduct` being purchased — it must belong to that product.
 @param paymentDiscount payment discount signed for the current user; an unsigned or foreign discount fails the purchase with an `SKError`.
 */
- (instancetype)initWithProductDiscount:(SKProductDiscount *)productDiscount paymentDiscount:(SKPaymentDiscount *)paymentDiscount;
#pragma clang diagnostic pop

@end

NS_ASSUME_NONNULL_END
