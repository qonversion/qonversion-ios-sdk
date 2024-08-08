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

- (instancetype)initWithQuantity:(NSInteger)quantity contextKeys:(NSArray * _Nullable)contextKeys {
  self = [super init];
  
  if (self) {
    _quantity = quantity;
    _contextKeys = contextKeys;
  }
  
  return self;
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
