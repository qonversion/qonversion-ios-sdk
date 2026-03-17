//
//  QONDeferredPurchasesListener.h
//  Qonversion
//

#import <Foundation/Foundation.h>

@class QONDeferredTransaction;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.DeferredPurchasesListener)
@protocol QONDeferredPurchasesListener <NSObject>

/**
 Called when a deferred purchase completes.
 For example, when pending purchases like SCA, Ask to Buy, etc., are approved and finalized.
 Provides full transaction details, including for consumable products without entitlements.
 @param transaction - transaction details for the completed deferred purchase.
 */
- (void)deferredPurchaseCompleted:(QONDeferredTransaction * _Nonnull)transaction;

@end

NS_ASSUME_NONNULL_END
