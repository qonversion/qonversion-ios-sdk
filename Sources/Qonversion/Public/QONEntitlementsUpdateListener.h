//
//  QONEntitlementsUpdateListener.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONEntitlement.h"

NS_SWIFT_NAME(Qonversion.EntitlementsUpdateListener)
@protocol QONEntitlementsUpdateListener <NSObject>

- (void)didReceiveUpdatedEntitlements:(NSDictionary<NSString *, QONEntitlement *>  * _Nonnull)entitlements;

@end
