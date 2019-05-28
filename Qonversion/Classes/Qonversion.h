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

+ (void)launchWithKey:(NSString *)key autoTrackPurchases:(BOOL)autoTrack completion:(void (^)(NSString *uid))completion;
+ (void)trackPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
