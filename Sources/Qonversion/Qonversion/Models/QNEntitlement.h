//
//  QNEntitlement.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNPurchase;

NS_ASSUME_NONNULL_BEGIN

@interface QNEntitlement : NSObject

@property (nonatomic, copy, readonly) NSString *entitlementID;
@property (nonatomic, copy, readonly) NSString *userID;
@property (nonatomic, assign, readonly) BOOL active;
@property (nonatomic, strong, readonly) NSDate *startedDate;
@property (nonatomic, strong, readonly) NSDate *expirationDate;
@property (nonatomic, copy, readonly) NSArray<QNPurchase *> *purchases;
@property (nonatomic, copy, readonly) NSString *object;

@end

NS_ASSUME_NONNULL_END
