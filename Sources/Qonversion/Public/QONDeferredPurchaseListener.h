//
//  QONDeferredPurchaseListener.h
//  Qonversion
//

#import <Foundation/Foundation.h>

@class QONEntitlement;
@class QONPurchaseResult;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.DeferredPurchaseListener)
@protocol QONDeferredPurchaseListener <NSObject>

/**
 Called when a deferred purchase completes.
 For example, when pending purchases like SCA, Ask to Buy, etc., are approved and finalized.
 @param entitlements - the user's entitlements after the deferred purchase completion.
 @param purchaseResult - the purchase result with transaction details.
 */
- (void)didCompleteDeferredPurchaseWithEntitlements:(NSDictionary<NSString *, QONEntitlement *> * _Nonnull)entitlements
                                     purchaseResult:(QONPurchaseResult * _Nonnull)purchaseResult;

@end

NS_ASSUME_NONNULL_END
