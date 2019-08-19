//
//  Keeper.m
//  Qonversion
//
//  Created by Bogdan Novikov on 24/05/2019.
//

#import "Keeper.h"
#import "Keychain.h"

@implementation Keeper

+ (nullable NSString *)userID {
    return [Keychain stringForKey:@"Qonversion.Keeper.userID"];
}

+ (void)setUserID:(NSString *)userID {
    [Keychain setString:userID forKey:@"Qonversion.Keeper.userID"];
}

@end
