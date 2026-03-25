//
//  QONDeferredPurchasesListener.h
//  Qonversion
//

#import <Foundation/Foundation.h>

@class QONPurchaseResult;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.DeferredPurchasesListener)
@protocol QONDeferredPurchasesListener <NSObject>

/**
 Called when a deferred purchase completes.
 For example, when pending purchases like SCA, Ask to Buy, etc., are approved and finalized.
 Provides the purchase result with entitlements.
 @param purchaseResult - the result of the completed deferred purchase, containing entitlements.
 */
- (void)deferredPurchaseCompleted:(QONPurchaseResult * _Nonnull)purchaseResult;

@end

NS_ASSUME_NONNULL_END
