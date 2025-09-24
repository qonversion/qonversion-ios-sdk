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
 * Initialize purchase result with entitlements and transaction.
 * @param entitlements Dictionary of entitlements granted
 * @param transaction StoreKit transaction
 * @return QONPurchaseResult instance
 */
- (instancetype)initWithEntitlements:(nullable NSDictionary<NSString *, QONEntitlement *> *)entitlements
                         transaction:(nullable SKPaymentTransaction *)transaction;

/**
 * Initialize purchase result with error and cancellation status.
 * @param error Error that occurred during purchase
 * @param isUserCanceled Whether the user canceled the purchase
 * @return QONPurchaseResult instance
 */
- (instancetype)initWithError:(nullable NSError *)error
               isUserCanceled:(BOOL)isUserCanceled;

/**
 * Initialize purchase result with error, transaction and cancellation status.
 * @param error Error that occurred during purchase
 * @param transaction StoreKit transaction
 * @param isUserCanceled Whether the user canceled the purchase
 * @return QONPurchaseResult instance
 */
- (instancetype)initWithError:(nullable NSError *)error
                   transaction:(nullable SKPaymentTransaction *)transaction
               isUserCanceled:(BOOL)isUserCanceled;

/**
 * Initialize purchase result with all parameters.
 * @param entitlements Dictionary of entitlements granted
 * @param error Error that occurred during purchase
 * @param transaction StoreKit transaction
 * @param isUserCanceled Whether the user canceled the purchase
 * @return QONPurchaseResult instance
 */
- (instancetype)initWithEntitlements:(nullable NSDictionary<NSString *, QONEntitlement *> *)entitlements
                               error:(nullable NSError *)error
                         transaction:(nullable SKPaymentTransaction *)transaction
                     isUserCanceled:(BOOL)isUserCanceled;

@end

NS_ASSUME_NONNULL_END

