//
//  QNEntitlement+Protected.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 20.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNEntitlement.h"

NS_ASSUME_NONNULL_BEGIN

@interface QNEntitlement (Protected)

- (instancetype)initWithID:(NSString *)entitlementID
                    userID:(NSString *)userID
                    active:(BOOL)active
               startedDate:(NSDate *)startedDate
            expirationDate:(NSDate *)expirationDate
                 purchases:(NSArray<QNPurchase *> *)purchases
                    object:(NSString *)object;

@end

NS_ASSUME_NONNULL_END
