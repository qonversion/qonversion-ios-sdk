//
//  QONTransaction+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.12.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONTransaction.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONTransaction (Protected)

- (instancetype)initWithOriginalTransactionId:(NSString *)originalTransactionId
                                transactionId:(NSString *)transactionId
                                    offerCode:(NSString *)offerCode
                              transactionDate:(NSDate *)transactionDate
                               expirationDate:(NSDate *)expirationDate
                    transactionRevocationDate:(NSDate *)transactionRevocationDate
                                 promoOfferId:(NSString *)promoOfferId
                                  environment:(QONTransactionEnvironment)environment
                                ownershipType:(QONTransactionOwnershipType)ownershipType
                                         type:(QONTransactionType)type;

- (instancetype)initWithOriginalTransactionId:(NSString *)originalTransactionId
                                transactionId:(NSString *)transactionId
                                    offerCode:(NSString *)offerCode
                              transactionDate:(NSDate *)transactionDate
                               expirationDate:(NSDate *)expirationDate
                    transactionRevocationDate:(NSDate *)transactionRevocationDate
                                 promoOfferId:(NSString *)promoOfferId
                                  environment:(QONTransactionEnvironment)environment
                                ownershipType:(QONTransactionOwnershipType)ownershipType
                                         type:(QONTransactionType)type
                               commitmentInfo:(nullable QONTransactionCommitmentInfo *)commitmentInfo API_AVAILABLE(ios(26.4), macosx(26.4), watchos(26.4), tvos(26.4), visionos(26.4));

@end

NS_ASSUME_NONNULL_END
