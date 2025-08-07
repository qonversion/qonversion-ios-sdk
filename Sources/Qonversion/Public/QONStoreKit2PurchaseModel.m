//
//  QONStoreKit2PurchaseModel.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONStoreKit2PurchaseModel.h"

@implementation QONStoreKit2PurchaseModel

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"productId=%@,\n", self.productId];
  [description appendFormat:@"price=%@,\n", self.price];
  [description appendFormat:@"currency=%@,\n", self.currency];
  [description appendFormat:@"transactionId=%@,\n", self.transactionId];
  [description appendFormat:@"originalTransactionId=%@,\n", self.originalTransactionId];
  [description appendFormat:@"subscriptionPeriodUnit=%@,\n", self.subscriptionPeriodUnit];
  [description appendFormat:@"subscriptionPeriodNumberOfUnits=%@,\n", self.subscriptionPeriodNumberOfUnits];
  [description appendFormat:@"introductoryPrice=%@,\n", self.introductoryPrice];
  [description appendFormat:@"introductoryNumberOfPeriods=%@,\n", self.introductoryNumberOfPeriods];
  [description appendFormat:@"introductoryPeriodUnit=%@,\n", self.introductoryPeriodUnit];
  [description appendFormat:@"introductoryPeriodNumberOfUnits=%@,\n", self.introductoryPeriodNumberOfUnits];
  [description appendFormat:@"introductoryPaymentMode=%@,\n", self.introductoryPaymentMode];
  [description appendFormat:@"promoOfferId=%@,\n", self.promoOfferId];
  [description appendFormat:@"promoOfferPrice=%@,\n", self.promoOfferPrice];
  [description appendFormat:@"promoOfferNumberOfPeriods=%@,\n", self.promoOfferNumberOfPeriods];
  [description appendFormat:@"promoOfferPeriodUnit=%@,\n", self.promoOfferPeriodUnit];
  [description appendFormat:@"promoOfferPeriodNumberOfUnits=%@,\n", self.promoOfferPeriodNumberOfUnits];
  [description appendFormat:@"promoOfferPaymentMode=%@,\n", self.promoOfferPaymentMode];
  [description appendFormat:@"storefrontCountryCode=%@,\n", self.storefrontCountryCode];
  [description appendString:@">"];
  
  return [description copy];
}

@end
