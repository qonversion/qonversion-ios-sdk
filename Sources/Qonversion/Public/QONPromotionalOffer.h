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
API_AVAILABLE(ios(12.2), macos(10.14.4), watchos(6.2), visionos(1.0))
@interface QONPromotionalOffer : NSObject

@property (nonatomic, strong) SKProductDiscount *productDiscount;
@property (nonatomic, strong) SKPaymentDiscount *paymentDiscount;

@end

NS_ASSUME_NONNULL_END
