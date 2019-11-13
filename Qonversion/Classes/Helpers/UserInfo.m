//
//  UserInfo.m
//  Qonversion
//
//  Created by Bogdan Novikov on 23/05/2019.
//

#import "UserInfo.h"
#import <sys/utsname.h>
#import <AdSupport/AdSupport.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <Keeper.h>

static NSString *QInternalUserIDKey = @"QInternalUserIDKey";

@interface UserInfo (InternalUserID)

+ (NSString *)internalUserID;

@end

@implementation UserInfo

+ (nullable NSBundle *)bundle {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"appStoreReceiptURL != nil"];
    return [NSBundle.allBundles filteredArrayUsingPredicate:predicate].firstObject;
}

+ (NSDictionary *)overallData {
    NSMutableDictionary *dict = NSMutableDictionary.new;
    dict[@"internalUserID"] = [self internalUserID];

    if (self.bundle) {
        dict[@"app"] = @{@"name": self.bundle.name,
                         @"version": self.bundle.version,
                         @"build": self.bundle.build,
                         @"bundle": self.bundle.bundleIdentifier};
    }

    NSMutableDictionary *adsDict = @{@"trackingEnabled": [NSNumber numberWithBool:ASIdentifierManager.sharedManager.isAdvertisingTrackingEnabled].stringValue}.mutableCopy;

    if (ASIdentifierManager.sharedManager.isAdvertisingTrackingEnabled) {
        adsDict[@"IDFA"] = ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString;
    }

    dict[@"device"] = @{@"os": @{@"name": UIDevice.currentDevice.systemName,
                                 @"version": UIDevice.currentDevice.systemVersion},
                        @"screen": @{@"height": [NSNumber numberWithFloat:UIScreen.mainScreen.size.height].stringValue,
                                     @"width": [NSNumber numberWithFloat:UIScreen.mainScreen.size.width].stringValue},
                        @"ads": adsDict,
                        @"deviceId": UIDevice.currentDevice.identifierForVendor.UUIDString,
                        @"model": UIDevice.currentDevice.model,
                        @"carrier": CTTelephonyNetworkInfo.new.subscriberCellularProvider.carrierName ?: @"",
                        @"locale": NSLocale.currentLocale.localeIdentifier,
                        @"timezone": NSTimeZone.localTimeZone.name};
    return dict;
}

+ (void)saveInternalUserID:(nonnull NSString *)uid {
    [[NSUserDefaults standardUserDefaults] setObject:uid forKey:QInternalUserIDKey];
}

+ (NSString *)internalUserID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:QInternalUserIDKey] ?: @"";
}

@end

@implementation NSBundle(Dict)

- (NSString *)name    { return self.infoDictionary[@"CFBundleDisplayName"] ?: self.infoDictionary[@"CFBundleName"] ?: @""; }
- (NSString *)version { return self.infoDictionary[@"CFBundleShortVersionString"] ?: @""; }
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
