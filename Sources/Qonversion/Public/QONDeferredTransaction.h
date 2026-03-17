//
//  QONDeferredTransaction.h
//  Qonversion
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents the type of a deferred transaction.
 */
typedef NS_ENUM(NSInteger, QONDeferredTransactionType) {
    QONDeferredTransactionTypeUnknown = -1,
    QONDeferredTransactionTypeSubscription = 0,
    QONDeferredTransactionTypeConsumable = 1,
    QONDeferredTransactionTypeNonConsumable = 2
} NS_SWIFT_NAME(Qonversion.DeferredTransactionType);

NS_SWIFT_NAME(Qonversion.DeferredTransaction)
/**
 * Represents a completed deferred purchase transaction with full details.
 */
@interface QONDeferredTransaction : NSObject

/**
 * Store product identifier.
 */
@property (nonatomic, copy, readonly) NSString *productId;

/**
 * Store transaction identifier.
 */
@property (nonatomic, copy, readonly, nullable) NSString *transactionId;

/**
 * Original store transaction identifier. For subscriptions, this is the ID of the first transaction.
 */
@property (nonatomic, copy, readonly, nullable) NSString *originalTransactionId;

/**
 * Type of the transaction: subscription, consumable, or non-consumable.
 */
@property (nonatomic, assign, readonly) QONDeferredTransactionType type;

/**
 * Transaction value. May be 0 if unavailable.
 */
@property (nonatomic, assign, readonly) double value;

/**
 * Currency code (e.g. "USD"). May be nil if unavailable.
 */
@property (nonatomic, copy, readonly, nullable) NSString *currency;

@end

NS_ASSUME_NONNULL_END
