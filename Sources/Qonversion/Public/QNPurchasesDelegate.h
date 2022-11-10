//
//  QNPurchasesDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNEntitlement.h"

NS_SWIFT_NAME(Qonversion.PurchasesDelegate)
@protocol QNPurchasesDelegate <NSObject>

- (void)qonversionDidReceiveUpdatedEntitlements:(NSDictionary<NSString *, QNEntitlement *>  * _Nonnull)entitlements;

@end
