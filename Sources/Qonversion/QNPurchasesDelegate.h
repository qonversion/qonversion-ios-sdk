//
//  QNPurchasesDelegate.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QNPermission.h"

NS_SWIFT_NAME(Qonversion.PurchasesDelegate)
@protocol QNPurchasesDelegate <NSObject>

- (void)qonversionDidReceiveUpdatedPermissions:(NSDictionary<NSString *, QNPermission *>  * _Nonnull)permissions;

@end
