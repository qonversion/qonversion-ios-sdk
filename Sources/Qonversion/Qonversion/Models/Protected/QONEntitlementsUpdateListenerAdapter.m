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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)deferredPurchaseCompleted:(QONPurchaseResult *)purchaseResult {
  [self.legacyListener didReceiveUpdatedEntitlements:purchaseResult.entitlements ?: @{}];
}
#pragma clang diagnostic pop

@end
