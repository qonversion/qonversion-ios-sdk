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
  QONTransactionTypeUnknown = 0,
  QONTransactionTypeSubscriptionStarted = 1,
  QONTransactionTypeSubscriptionRenewed = 2,
  QONTransactionTypeTrialStarted = 3,
  QONTransactionTypeIntroStarted = 4,
  QONTransactionTypeIntroRenewed = 5,
  QONTransactionTypeNonConsumablePurchase = 6
 } NS_SWIFT_NAME(Qonversion.TransactionType);

NS_SWIFT_NAME(Qonversion.Transaction)
@interface QONTransaction : NSObject <NSCoding>

/**
 Original transaction identifier.
 */
@property (nonatomic, copy, nonnull) NSString *originalTransactionId;

/**
 Transaction identifier.
 */
@property (nonatomic, copy, nonnull) NSString *transactionId;

/**
 Offer code.
 */
@property (nonatomic, copy, nullable) NSString *offerCode;

/**
 Transaction date.
 */
@property (nonatomic, strong, nonnull) NSDate *transactionDate;

/**
 Expiration date for subscriptions.
 */
@property (nonatomic, strong, nullable) NSDate *expirationDate;

/**
 The date when transaction was revoked. This field represents the time and date the App Store refunded a transaction or revoked it from family sharing.
 */
@property (nonatomic, strong, nullable) NSDate *transactionRevocationDate;

/**
 Environment of the transaction.
 */
@property (nonatomic, assign) QONTransactionEnvironment environment;

/**
 Type of ownership for the transaction.  Owner/Family sharing.
 */
@property (nonatomic, assign) QONTransactionOwnershipType ownershipType;

/**
 Type of the transaction.
 */
@property (nonatomic, assign) QONTransactionType type;

@end

NS_ASSUME_NONNULL_END
