//
//  AppDelegate.m
//  ObjcEx
//
//  Created by Bogdan Novikov on 21/05/2019.
//  Copyright © 2019 axcic. All rights reserved.
//

#import "AppDelegate.h"
#import "Qonversion.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [Qonversion launchWithKey:@"projectKey" autoTrackPurchases:YES completion:^(NSString * _Nonnull uid) {
        // need to pass uid to FBSDKCoreKit.AppEvents.userID
    }];
    
    return YES;
}

@end
