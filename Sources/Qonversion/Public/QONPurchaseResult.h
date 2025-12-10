//
//  QONPurchaseResult.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

@class QONEntitlement;

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents the status of a purchase operation result.
 * - Success: The purchase was completed successfully (either through the API or fallback system)
 * - UserCanceled: The user canceled the purchase
 * - Pending: The purchase is pending (awaiting completion)
 * - Error: The purchase failed due to an error (and fallback system could not handle it)
 */
typedef NS_ENUM(NSInteger, QONPurchaseResultStatus) {
    QONPurchaseResultStatusSuccess = 0,
    QONPurchaseResultStatusUserCanceled = 1,
    QONPurchaseResultStatusPending = 2,
    QONPurchaseResultStatusError = 3
} NS_SWIFT_NAME(Qonversion.PurchaseResultStatus);

/**
 * Represents the source of a purchase result.
 * - Api: The purchase result was obtained from the Qonversion API.
 * - Local: The purchase result was generated locally by the Qonversion SDK fallback system.
 */
typedef NS_ENUM(NSInteger, QONPurchaseResultSource) {
    QONPurchaseResultSourceApi = 0,
    QONPurchaseResultSourceLocal = 1
} NS_SWIFT_NAME(Qonversion.PurchaseResultSource);

NS_SWIFT_NAME(Qonversion.PurchaseResult)
/**
 * Represents the result of a purchase operation.
 * Contains all relevant information about the purchase outcome including entitlements,
 * errors, purchase details, and user cancellation status.
 */
@interface QONPurchaseResult : NSObject

/**
 * Status of the purchase operation: Success, UserCanceled, Pending, or Error
 */
@property (nonatomic, assign, readonly) QONPurchaseResultStatus status;

/**
 * Dictionary of entitlements current user has after the purchase.
 * Key is entitlement identifier, value is QONEntitlement object.
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, QONEntitlement *> *entitlements;

/**
 * StoreKit transaction associated with the purchase.
 * Can be nil if the purchase failed before reaching StoreKit.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@property (nonatomic, strong, readonly, nullable) SKPaymentTransaction *transaction;
#pragma clang diagnostic pop

/**
 * Error that occurred during the purchase process, if any.
 */
@property (nonatomic, strong, readonly, nullable) NSError *error;

/**
 * Source of this purchase result: Api or Local (fallback system)
 */
@property (nonatomic, assign, readonly) QONPurchaseResultSource source;

/**
 * Indicates whether the entitlements were generated locally (by Qonversion SDK fallback system)
 */
@property (nonatomic, assign, readonly) BOOL isFallbackGenerated;

/**
 * Indicates whether the purchase was completed successfully (either through the API or fallback system)
 */
@property (nonatomic, assign, readonly) BOOL isSuccessful;

/**
 * Indicates whether the user canceled the purchase.
 * This is different from a purchase failure - cancellation is user-initiated.
 */
@property (nonatomic, assign, readonly) BOOL isCanceledByUser;

/**
 * Indicates whether the purchase is pending (awaiting completion)
 */
@property (nonatomic, assign, readonly) BOOL isPending;

/**
 * Indicates whether the purchase failed due to an error
 */
@property (nonatomic, assign, readonly) BOOL isError;

@end

NS_ASSUME_NONNULL_END
