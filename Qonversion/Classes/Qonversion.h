//
//  Qonversion.h
//  Qonversion
//
//  Created by Bogdan Novikov on 05/05/2019.
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface Qonversion : NSObject

/**
 Initializes an instance of the Qonversion SDK with the given project key.
 
 @param key The key used to setup the SDK.
 @param autoTrack Tracks all purchase events automatically (purchases, subscriptions or trials). With this parameter turned on you don't need to use `trackPurchase:transaction:` method.
 
 @warning With `autoTrackPurchases` disabled you have to call `trackPurchase:transaction:` method. Otherwise, purchase tracking won't work.
 */
+ (void)launchWithKey:(NSString *)key autoTrackPurchases:(BOOL)autoTrack;

/**
 Tracks porchases manually. Do nothing if you pass `true` for `autoTrackPurchases` in `launchWithKey:autoTrackPurchases:` method.
 
 @param product SKProduct. Any type: purchase, subscription or trial.
 @param transaction SKPaymentTransaction of the product.
 */
+ (void)trackPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
