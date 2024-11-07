//
//  QONPurchaseOptions.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 25.07.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONPurchaseOptions.h"

@implementation QONPurchaseOptions

- (instancetype)initWithQuantity:(NSInteger)quantity {
  return [self initWithQuantity:quantity contextKeys:nil];
}

- (instancetype)initWithContextKeys:(NSArray<NSString *> * _Nullable)contextKeys {
  return [self initWithQuantity:1 contextKeys:contextKeys];
}

- (instancetype)initWithQuantity:(NSInteger)quantity contextKeys:(NSArray<NSString *>  * _Nullable)contextKeys {
  return [self initWithQuantity:quantity contextKeys:contextKeys promoOffer:nil];
}

- (instancetype)initWithQuantity:(NSInteger)quantity contextKeys:(NSArray<NSString *>  * _Nullable)contextKeys promoOffer:(QONPromotionalOffer * _Nullable)promoOffer {
  self = [super init];
  
  if (self) {
    _quantity = quantity;
    _contextKeys = contextKeys;
    _promoOffer = promoOffer;
  }
  
  return self;
}

- (instancetype)initWithPromoOffer:(QONPromotionalOffer *)promoOffer {
  return [self initWithQuantity:1 contextKeys:nil promoOffer:promoOffer];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _quantity = [coder decodeIntForKey:NSStringFromSelector(@selector(quantity))];
    _contextKeys = [coder decodeObjectForKey:NSStringFromSelector(@selector(contextKeys))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeInteger:_quantity forKey:NSStringFromSelector(@selector(quantity))];
  [coder encodeObject:_contextKeys forKey:NSStringFromSelector(@selector(contextKeys))];
}

@end
