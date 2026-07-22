//
//  QONStoreKit2PurchaseModel.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONTransactionCommitmentInfo.h"

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
@property (nonatomic, copy, nullable) NSString *promoOfferId;
@property (nonatomic, copy, nullable) NSString *promoOfferPrice;
@property (nonatomic, copy, nullable) NSString *promoOfferNumberOfPeriods;
@property (nonatomic, copy, nullable) NSString *promoOfferPeriodUnit;
@property (nonatomic, copy, nullable) NSString *promoOfferPeriodNumberOfUnits;
@property (nonatomic, copy, nullable) NSString *promoOfferPaymentMode;
@property (nonatomic, copy, nullable) NSString *storefrontCountryCode;

/**
 Commitment info parsed from the local StoreKit2 transaction (iOS 26.4+).
 Populated in PurchasesMapper from Transaction.jsonRepresentation and forwarded to
 QONTransaction once the Qonversion backend includes commitment data in transaction responses.
 */
@property (nonatomic, strong, nullable) QONTransactionCommitmentInfo *commitmentInfo API_AVAILABLE(ios(26.4), macosx(26.4), watchos(26.4), tvos(26.4), visionos(26.4));

@end

NS_ASSUME_NONNULL_END
