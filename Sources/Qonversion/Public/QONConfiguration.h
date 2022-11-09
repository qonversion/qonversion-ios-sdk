//
//  QONConfiguration.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchMode.h"
#import "QNEntitlementsCacheLifetime.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.Configuration)
@interface QONConfiguration : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *projectKey;
@property (nonatomic, assign, readonly) QONLaunchMode launchMode;
@property (nonatomic, assign, readonly) QNEntitlementsCacheLifetime *entitlementsCacheLifetime;
@property (nonatomic, assign, readonly) QONEnvironment environment;
@property (nonatomic, weak, readonly) id<QONEntitlementsUpdateListener> entitlementsUpdateListener;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithProjectKey:(NSString  * _Nonnull)projectKey
                        launchMode:(QONLaunchMode)launchMode NS_DESIGNATED_INITIALIZER;

/**
 Entitlements cache is used when there are problems with the Qonversion API or internet connection.
 If so, Qonversion will return the last successfully loaded entitlements. The current method allows you to configure how long that cache may be used.
 The default value is QNEntitlementCacheLifetimeMonth.
 @param cacheLifetime desired entitlements cache lifetime duration
 */
- (void)setEntitlementsCacheLifetime:(QNEntitlementsCacheLifetime)cacheLifetime;

/**
 Set this listener to handle pending purchases like SCA, Ask to buy, etc
 The delegate will be called when the deferred transaction status updates
 @param listener - listener for handling deferred purchases
 */
- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)entitlementsUpdateListener;

- (void)setEnvironment:(QONEnvironment)environment;

- (id)copyWithZone:(NSZone * _Nullable)zone;

@end

NS_ASSUME_NONNULL_END
