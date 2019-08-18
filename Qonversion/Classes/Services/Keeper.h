//
//  Keeper.h
//  Qonversion
//
//  Created by Bogdan Novikov on 24/05/2019.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Keeper : NSObject

+ (nullable NSString *)userID;
+ (void)setUserID:(NSString *)userID;

+ (nullable NSString *)initialIP;
+ (void)setInitialIP:(NSString *)initialIP;

@end

NS_ASSUME_NONNULL_END
 
