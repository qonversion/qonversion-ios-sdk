//
//  QONEntitlementsUpdateListener.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONEntitlement.h"

@class QONPurchaseResult;

NS_SWIFT_NAME(Qonversion.EntitlementsUpdateListener)
@protocol QONEntitlementsUpdateListener <NSObject>

/// Called when user entitlements are updated asynchronously (e.g. deferred purchases, SCA, Ask to Buy).
- (void)didReceiveUpdatedEntitlements:(NSDictionary<NSString *, QONEntitlement *>  * _Nonnull)entitlements;

@optional

/// Called when user entitlements are updated asynchronously with associated purchase result.
/// For consumable purchases that complete in the background, entitlements may be empty
/// while purchaseResult contains the purchase details.
/// @param entitlements all current entitlements of the user.
/// @param purchaseResult the purchase result associated with this update, if available.
- (void)didReceiveUpdatedEntitlements:(NSDictionary<NSString *, QONEntitlement *>  * _Nonnull)entitlements
                       purchaseResult:(QONPurchaseResult * _Nullable)purchaseResult;

@end
