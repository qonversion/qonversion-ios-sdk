//
//  QNUser.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 14.05.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QNEntitlement, QNPurchase;

NS_ASSUME_NONNULL_BEGIN

@interface QNUser : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSArray<QNEntitlement *> *entitlements;
@property (nonatomic, copy, readonly) NSArray<QNPurchase *> *purchases;
@property (nonatomic, copy, readonly) NSString *object;
@property (nonatomic, strong, readonly) NSDate *createDate;
@property (nonatomic, strong, readonly) NSDate *lastOnlineDate;
@property (nonatomic, copy, readonly) NSString *originalAppVersion;

@end

NS_ASSUME_NONNULL_END
