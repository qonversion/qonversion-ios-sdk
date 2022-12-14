//
//  QONConfiguration.h
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchMode.h"
#import "QONEntitlementsCacheLifetime.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONEnvironment.h"
#import "QONPromoPurchasesDelegate.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Qonversion.Configuration)
@interface QONConfiguration : NSObject <NSCopying>

/**
 Your project key from Qonversion Dashboard to setup the SDK
 */
@property (nonatomic, copy, readonly) NSString *projectKey;

/**
 Version of Qonversion SDK
 */
@property (nonatomic, copy, readonly) NSString *version;

/**
 Launch mode of the Qonversion SDK.
 Launch with QONLaunchModeAnalytics (former Observer) mode to use Qonversion with your existing in-app subscription flow to get comprehensive subscription analytics and user engagement tools, and send the data to the leading marketing, analytics, and engagement platforms.
 Launch with QONLaunchModeSubscriptionManagement (former Infrastructure) mode to use Qonversion SDK or API methods to process your In-App & Stripe purchases and to manage user access to the premium features. SubscriptionManagement mode includes  Analytics mode.
 */
@property (nonatomic, assign, readonly) QONLaunchMode launchMode;

/**
 Lifetime for an entitlements cache.
 Entitlements cache is used when there are problems with the Qonversion API or internet connection.
 The default value is QONEntitlementsCacheLifetimeMonth.
 */
@property (nonatomic, assign, readonly) QONEntitlementsCacheLifetime entitlementsCacheLifetime;
         
/**
 Current application Environment. Used to distinguish sandbox and production users.
 The default value is QONEnvironmentProduction.
 */
@property (nonatomic, assign, readonly) QONEnvironment environment;

/**
 Listener to handle entitlements update. For example, when pending purchases like SCA, Ask to buy, etc., happened.
 */
@property (nonatomic, weak, readonly) id<QONEntitlementsUpdateListener> entitlementsUpdateListener;

/**
 Delegate to handle App Store Promo purchases.
 */
@property (nonatomic, weak, readonly) id<QONPromoPurchasesDelegate> promoPurchasesDelegate;

- (instancetype)init NS_UNAVAILABLE;

/**
 Initialize the SDK's Configuration with required parameters.
 @param projectKey - your project key from Qonversion Dashboard
 @param launchMode - launch mode of the Qonversion SDK
 */
- (instancetype)initWithProjectKey:(NSString  * _Nonnull)projectKey
                        launchMode:(QONLaunchMode)launchMode NS_DESIGNATED_INITIALIZER;

/**
 Entitlements cache is used when there are problems with the Qonversion API or internet connection.
 If so, Qonversion will return the last successfully loaded entitlements. The current method allows you to configure how long that cache may be used.
 The default value is QNEntitlementCacheLifetimeMonth.
 @param cacheLifetime desired entitlements cache lifetime duration
 */
- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime;

/**
 Set this listener to handle entitlements update. For example, when pending purchases like SCA, Ask to buy, etc., happened.
 @param entitlementsUpdateListener - listener for handling entitlements update
 */
- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)entitlementsUpdateListener;

/**
 Set this delegate to handle AppStore promo purchases
 @param delegate - delegate for handling AppStore promo purchase flow
 */
- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate;

/**
 Set the current application Environment. Used to distinguish sandbox and production users.
 Please don't use QONEnvironmentSandbox for the production app. Enable Sandbox mode only while developing.
 The default value is QONEnvironmentProduction.
 @param environment current environment
 */
- (void)setEnvironment:(QONEnvironment)environment;

- (id)copyWithZone:(NSZone * _Nullable)zone;

@end

NS_ASSUME_NONNULL_END
