#import "QConstants.h"
#import "QDevice.h"

#import "UserInfo.h"
#import "Keeper.h"

@interface UserInfo (InternalUserID)

+ (NSString *)internalUserID;

@end

@implementation UserInfo

+ (NSDictionary *)overallData {
    QDevice *device = [[QDevice alloc] init];
    NSMutableDictionary *overallDict = [NSMutableDictionary new];
    
    if ([self internalUserID]) {
        [overallDict setValue:[self internalUserID] forKey:@"internalUserID"];
    }
    
    if (device.appVersion) {
        [overallDict setValue:device.appVersion forKey:@"appVersion"];
    }
    
    [overallDict setValue:[UserInfo appStoreReceipt] ?: @"" forKey:@"receipt"];
    
    
    NSMutableDictionary *deviceDict = [NSMutableDictionary new];
    NSMutableDictionary *osDict = [NSMutableDictionary new];
    
    
    if (device.osName) {
        [osDict setValue:device.osName forKey:@"name"];
    }
    
    if (device.osVersion) {
        [osDict setValue:device.osVersion forKey:@"version"];
    }
    
    if (device.manufacturer) {
        [osDict setValue:device.manufacturer forKey:@"manufacturer"];
    }
    
    [deviceDict setValue:osDict.copy forKey:@"os"];
    
    NSMutableDictionary *adsDict = [NSMutableDictionary new];

    // Need to replace with public method
    [adsDict setValue:@"1" forKey:@"trackingEnabled"];
    if (device.advertiserID) {
        [adsDict setValue:device.advertiserID forKey:@"IDFA"];
    }
    
    [deviceDict setValue:adsDict.copy forKey:@"ads"];
    
    if (device.vendorID) {
        [deviceDict setValue:device.vendorID forKey:@"deviceId"];
    }
    
    if (device.model) {
        [deviceDict setValue:device.model forKey:@"model"];
    }
    
    if (device.carrier) {
        [deviceDict setValue:device.carrier forKey:@"carrier"];
    }
    
    if (device.language) {
        [deviceDict setValue:device.language forKey:@"locale"];
    }
    
    if (device.country) {
        [deviceDict setValue:device.country forKey:@"country"];
    }
    
    if (device.timezone) {
        [deviceDict setValue:device.timezone forKey:@"timezone"];
    }
    
    [overallDict setValue:deviceDict forKey:@"device"];
    
    return overallDict;
}

+ (nullable NSString *)appStoreReceipt {
    NSURL *receiptURL = UserInfo.bundle.appStoreReceiptURL;
    
    if (!receiptURL) {
        return NULL;
    }

    NSString *receipt = [[NSData dataWithContentsOfURL:receiptURL] base64EncodedStringWithOptions:0];
    
    return receipt ?: @"";
}

+ (void)saveInternalUserID:(nonnull NSString *)uid {
    [[NSUserDefaults standardUserDefaults] setObject:uid forKey:keyQInternalUserID];
}

+ (NSString *)internalUserID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:keyQInternalUserID] ?: @"";
}

+ (nullable NSBundle *)bundle {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"appStoreReceiptURL != nil"];
    return [NSBundle.allBundles filteredArrayUsingPredicate:predicate].firstObject;
}

@end
