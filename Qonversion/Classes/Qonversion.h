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
 @param autoTrack Tracks all purchases automatically (purchase, subscription or trial). With this parameter turned on usage of the method `trackPurchase:transaction:` is unnecessary.
 @param completion Returns UID. You have to pass this UID to the `FBSDKCoreKit.AppEvents.userID`.
 
 @warning With `autoTrackPurchases` disabled you have to call `trackPurchase:`. Otherwise, purchase tracking won't track.
 */
+ (void)launchWithKey:(NSString *)key autoTrackPurchases:(BOOL)autoTrack completion:(void (^)(NSString *uid))completion;

/**
 Initializes an instance of the Qonversion SDK with the given project key.
 
 @param product SKProduct. Any type: purchase, subscription or trial.
 @param transaction SKPaymentTransaction of the same purchase.
 */
+ (void)trackPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
