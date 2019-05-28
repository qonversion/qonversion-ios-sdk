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

+ (nullable NSString *)initialIP {
    return [NSUserDefaults.standardUserDefaults stringForKey:@"Qonversion.Keeper.initialIP"];
}

+ (void)setInitialIP:(NSString *)initialIP {
    [NSUserDefaults.standardUserDefaults setObject:initialIP forKey:@"Qonversion.Keeper.initialIP"];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end
