//
//  UserInfo.m
//  Qonversion
//
//  Created by Bogdan Novikov on 23/05/2019.
//

#import "UserInfo.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#import <AdSupport/AdSupport.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <Keeper.h>

@implementation UserInfo

+ (nullable NSBundle *)bundle {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"appStoreReceiptURL != nil"];
    return [NSBundle.allBundles filteredArrayUsingPredicate:predicate].firstObject;
}

+ (NSDictionary *)overallData {
    NSMutableDictionary *dict = NSMutableDictionary.new;
    if (self.bundle) {
        dict[@"app"] = @{@"name": self.bundle.name,
                         @"version": self.bundle.version,
                         @"build": self.bundle.build,
                         @"bundle": self.bundle.bundleIdentifier};
    }
    dict[@"device"] = @{@"os": @{@"name": UIDevice.currentDevice.systemName,
                                 @"version": UIDevice.currentDevice.systemVersion},
                        @"screen": @{@"height": [NSNumber numberWithFloat:UIScreen.mainScreen.size.height].stringValue,
                                     @"width": [NSNumber numberWithFloat:UIScreen.mainScreen.size.width].stringValue},
                        @"ads": @{@"trackingEnabled": [NSNumber numberWithBool:ASIdentifierManager.sharedManager.isAdvertisingTrackingEnabled].stringValue,
                                  @"IDFA": ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString},
                        @"deviceId": UIDevice.currentDevice.identifierForVendor.UUIDString,
                        @"model": UIDevice.currentDevice.model,
                        @"carrier": CTTelephonyNetworkInfo.new.subscriberCellularProvider.carrierName ?: @"none",
                        @"locale": NSLocale.currentLocale.localeIdentifier,
                        @"timezone": NSTimeZone.localTimeZone.name,
                        @"ip": Keeper.initialIP ?: @"none"};
    return dict;
}

@end

@implementation NSBundle(Dict)

- (NSString *)name    { return self.infoDictionary[@"CFBundleDisplayName"] ?: self.infoDictionary[@"CFBundleName"] ?: @""; }
- (NSString *)version { return self.infoDictionary[@"CFBundleShortVersionString"] ?: @"1.0"; }
- (NSString *)build   { return self.infoDictionary[@"CFBundleVersion"] ?: @""; }

@end

@implementation UIScreen(Size)

- (CGSize)size {
    if (UIScreen.mainScreen.bounds.size.height > UIScreen.mainScreen.bounds.size.width) {
        return UIScreen.mainScreen.bounds.size;
    }
    return CGSizeMake(UIScreen.mainScreen.bounds.size.height, UIScreen.mainScreen.bounds.size.width);
}

@end

@implementation UIDevice(Model)

- (NSString *)model {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

@end
