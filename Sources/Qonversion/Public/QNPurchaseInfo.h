//
//  QNPurchaseInfo.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 16.06.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

//NS_SWIFT_NAME(Qonversion.PurchaseInfo)
@interface QNPurchaseInfo : NSObject

@property (nonatomic, copy, nonnull) NSString *productId;
@property (nonatomic, copy, nonnull) NSString *price;
@property (nonatomic, copy, nonnull) NSString *currency;
@property (nonatomic, copy, nonnull) NSString *transactionId;
@property (nonatomic, copy, nonnull) NSString *originalTransactionId;
@property (nonatomic, copy, nullable) NSString *subscriptionPeriodUnit;
@property (nonatomic, copy, nullable) NSString *subscriptionPeriodNumberOfUnits;
@property (nonatomic, copy, nullable) NSString *introductoryPrice;
@property (nonatomic, copy, nullable) NSString *introductoryNumberOfPeriods;
@property (nonatomic, copy, nullable) NSString *introductoryPeriodUnit;
@property (nonatomic, copy, nullable) NSString *introductoryPeriodNumberOfUnits;
@property (nonatomic, copy, nullable) NSString *introductoryPaymentMode;
@property (nonatomic, copy, nullable) NSString *storefrontCountryCode;

@end
