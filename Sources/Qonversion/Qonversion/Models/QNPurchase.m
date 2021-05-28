//
//  QNPurchase.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNPurchase.h"

@implementation QNPurchase

- (instancetype)initWithUserID:(NSString *)userID
                    originalID:(NSString *)originalID
                    purchaseToken:(NSString *)purchaseToken
                      platform:(QNPurchasePlatform)platform
              platformRawValue:(NSString *)platformRawValue
             platformProductID:(NSString *)platformProductID
                       product:(QNUserProduct *)product
                      currency:(NSString *)currency
                        amount:(NSUInteger)amount
                  purchaseDate:(NSDate *)purchaseDate
                    createDate:(NSDate *)createDate
                        object:(NSString *)object {
  self = [super init];
  
  if (self) {
    _userID = userID;
    _originalID = originalID;
    _purchaseToken = purchaseToken;
    _platform = platform;
    _platformRawValue = platformRawValue;
    _platformProductID = platformProductID;
    _product = product;
    _currency = currency;
    _amount = amount;
    _purchaseDate = purchaseDate;
    _createDate = createDate;
    _object = object;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"userID=%@,\n", self.userID];
  [description appendFormat:@"originalID=%@,\n", self.originalID];
  [description appendFormat:@"purchaseToken=%@,\n", self.purchaseToken];
  [description appendFormat:@"platform=%@ (enum value = %li),\n", [self prettyPlatform], (long)self.platform];
  [description appendFormat:@"platformRawValue=%@", self.platformRawValue];
  [description appendFormat:@"platformProductID=%@", self.platformProductID];
  [description appendFormat:@"product=%@", self.product];
  [description appendFormat:@"currency=%@", self.currency];
  [description appendFormat:@"amount=%lu", (long unsigned)self.amount];
  [description appendFormat:@"purchaseDate=%@", self.purchaseDate];
  [description appendFormat:@"createDate=%@", self.createDate];
  [description appendFormat:@"object=%@", self.object];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyPlatform {
  NSString *result = @"unknown";
  
  switch (self.platform) {
    case QNPurchasePlatformIOS:
      result = @"iOS"; break;
    
    case QNPurchasePlatformAndroid:
      result = @"Android"; break;
    
    case QNPurchasePlatformStripe:
      result = @"Stripe"; break;
    
    case QNPurchasePlatformPromo:
      result = @"Promo"; break;
      
    default:
      break;
  }
  
  return result;
}

@end
