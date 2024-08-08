//
//  QONPromotionalOffer.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONPromotionalOffer.h"

@implementation QONPromotionalOffer

- (instancetype)initWithProductDiscount:(SKProductDiscount *)productDiscount paymentDiscount:(SKPaymentDiscount *)paymentDiscount {
  self = [super init];
  
  if (self) {
    _productDiscount = productDiscount;
    _paymentDiscount = paymentDiscount;
  }
  
  return self;
}

@end
