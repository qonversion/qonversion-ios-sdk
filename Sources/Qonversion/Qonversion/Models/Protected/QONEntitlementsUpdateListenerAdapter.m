//
//  QONEntitlementsUpdateListenerAdapter.m
//  Qonversion
//

#import "QONEntitlementsUpdateListenerAdapter.h"
#import "QONPurchaseResult.h"

@interface QONEntitlementsUpdateListenerAdapter ()

@property (nonatomic, weak) id<QONEntitlementsUpdateListener> legacyListener;

@end

@implementation QONEntitlementsUpdateListenerAdapter

- (instancetype)initWithLegacyListener:(id<QONEntitlementsUpdateListener>)legacyListener {
  self = [super init];
  if (self) {
    _legacyListener = legacyListener;
  }
  return self;
}

// Contract: deferredPurchaseCompleted: is only called with successful PurchaseResult
// (never error state). All call sites in QNProductCenterManager construct the result
// via successWithEntitlements: and guard with shouldNotify checks.
// This means the adapter always forwards valid entitlements to the legacy listener,
// preserving the original EntitlementsUpdateListener contract.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)deferredPurchaseCompleted:(QONPurchaseResult *)purchaseResult {
  [self.legacyListener didReceiveUpdatedEntitlements:purchaseResult.entitlements ?: @{}];
}
#pragma clang diagnostic pop

@end
