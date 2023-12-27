//
//  QONTransaction.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 20.12.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONTransactionEnvironment) {
  QONTransactionEnvironmentSandbox = 0,
  QONTransactionEnvironmentProduction = 1
 } NS_SWIFT_NAME(Qonversion.TransactionEnvironment);

typedef NS_ENUM(NSInteger, QONTransactionOwnershipType) {
  QONTransactionOwnershipTypeOwner = 0,
  QONTransactionOwnershipTypeFamilySharing = 1
 } NS_SWIFT_NAME(Qonversion.TransactionOwnershipType);

typedef NS_ENUM(NSInteger, QONTransactionType) {
  QONTransactionTypeSubscriptionStarted = 0,
  QONTransactionTypeSubscriptionRenewed = 1,
  QONTransactionTypeTrialStrated = 2,
  QONTransactionTypeIntroStarted = 3,
  QONTransactionTypeIntroRenewed = 4,
  QONTransactionTypeNonConsumablePurchase = 5
 } NS_SWIFT_NAME(Qonversion.TransactionType);

NS_SWIFT_NAME(Qonversion.Transaction)
@interface QONTransaction : NSObject <NSCoding>

@property (nonatomic, copy, nonnull) NSString *originalTransactionId;
@property (nonatomic, copy, nonnull) NSString *transactionId;
@property (nonatomic, copy, nullable) NSString *offerCode;
@property (nonatomic, strong, nonnull) NSDate *transactionDate;
@property (nonatomic, strong, nullable) NSDate *expirationDate;
@property (nonatomic, strong, nullable) NSDate *transactionRevocationDate;
@property (nonatomic, assign) QONTransactionEnvironment environment;
@property (nonatomic, assign) QONTransactionOwnershipType ownershipType;
@property (nonatomic, assign) QONTransactionType type;

@end

NS_ASSUME_NONNULL_END
