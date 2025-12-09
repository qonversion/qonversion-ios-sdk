//
//  QONPurchaseResult+Protected.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 18.12.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONPurchaseResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONPurchaseResult (Protected)

/**
 * Initialize purchase result with all parameters.
 * @param status Status of the purchase operation
 * @param entitlements Dictionary of entitlements granted
 * @param transaction StoreKit transaction
 * @param error Error that occurred during purchase
 * @param source Source of this purchase result
 * @return QONPurchaseResult instance
 */
- (instancetype)initWithStatus:(QONPurchaseResultStatus)status
                  entitlements:(nullable NSDictionary<NSString *, QONEntitlement *> *)entitlements
                   transaction:(nullable SKPaymentTransaction *)transaction
                         error:(nullable NSError *)error
                        source:(QONPurchaseResultSource)source;

// MARK: - Static Factory Methods

/**
 * Create a successful purchase result from API
 * @param entitlements Dictionary of entitlements granted
 * @param transaction StoreKit transaction
 * @return QONPurchaseResult instance with Success status and Api source
 */
+ (instancetype)successWithEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements
                            transaction:(SKPaymentTransaction *)transaction;

/**
 * Create a successful purchase result from fallback system
 * @param entitlements Dictionary of entitlements granted
 * @param transaction StoreKit transaction
 * @return QONPurchaseResult instance with Success status and Local source
 */
+ (instancetype)successFromFallbackWithEntitlements:(NSDictionary<NSString *, QONEntitlement *> *)entitlements
                                        transaction:(SKPaymentTransaction *)transaction;

/**
 * Create a user canceled purchase result
 * @return QONPurchaseResult instance with UserCanceled status
 */
+ (instancetype)userCanceled;

/**
 * Create a pending purchase result
 * @return QONPurchaseResult instance with Pending status
 */
+ (instancetype)pending;

/**
 * Create an error purchase result
 * @param error Error that occurred during purchase
 * @return QONPurchaseResult instance with Error status
 */
+ (instancetype)errorWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END

