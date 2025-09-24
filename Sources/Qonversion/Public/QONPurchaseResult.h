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

NS_SWIFT_NAME(Qonversion.PurchaseResult)
/**
 * Result of a purchase operation containing entitlements, error, transaction and cancellation status.
 */
@interface QONPurchaseResult : NSObject

/**
 * Dictionary of entitlements that were granted as a result of the purchase.
 * Key is entitlement identifier, value is QONEntitlement object.
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, QONEntitlement *> *entitlements;

/**
 * Error that occurred during the purchase process, if any.
 */
@property (nonatomic, strong, readonly, nullable) NSError *error;

/**
 * StoreKit transaction associated with the purchase.
 * Can be nil if the purchase failed before reaching StoreKit.
 */
@property (nonatomic, strong, readonly, nullable) SKPaymentTransaction *transaction;

/**
 * Indicates whether the user canceled the purchase.
 * This is different from a purchase failure - cancellation is user-initiated.
 */
@property (nonatomic, assign, readonly) BOOL isUserCanceled;


@end

NS_ASSUME_NONNULL_END
