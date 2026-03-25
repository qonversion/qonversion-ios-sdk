//
//  QONEntitlementsUpdateListenerAdapter.h
//  Qonversion
//

#import <Foundation/Foundation.h>
#import "QONDeferredPurchasesListener.h"
#import "QONEntitlementsUpdateListener.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Adapter that wraps a deprecated QONEntitlementsUpdateListener as a QONDeferredPurchasesListener.
 *
 * When the deprecated setEntitlementsUpdateListener: is called, this adapter allows
 * QNProductCenterManager to work with a single listener type internally
 * (QONDeferredPurchasesListener only), eliminating duplicate invocation logic.
 *
 * The adapter extracts entitlements from QONPurchaseResult and forwards them
 * to the wrapped legacy listener via didReceiveUpdatedEntitlements:.
 */
@interface QONEntitlementsUpdateListenerAdapter : NSObject <QONDeferredPurchasesListener>

- (instancetype)initWithLegacyListener:(id<QONEntitlementsUpdateListener>)legacyListener;

@end

NS_ASSUME_NONNULL_END
