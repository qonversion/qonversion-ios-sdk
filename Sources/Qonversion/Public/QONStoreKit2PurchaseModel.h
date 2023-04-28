//
//  QONStoreKit2PurchaseModel.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.StoreKit2PurchaseModel)
@interface QONStoreKit2PurchaseModel : NSObject

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

NS_ASSUME_NONNULL_END
