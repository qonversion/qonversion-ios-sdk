#import "QConstants.h"
#import "QDevice.h"

#import "UserInfo.h"
#import "Keeper.h"

@interface UserInfo (InternalUserID)

+ (NSString *)internalUserID;

@end

@implementation UserInfo

+ (nullable NSBundle *)bundle {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"appStoreReceiptURL != nil"];
    return [NSBundle.allBundles filteredArrayUsingPredicate:predicate].firstObject;
}

+ (NSDictionary *)overallData {
    QDevice *device = [[QDevice alloc] init];
    
    NSMutableDictionary *overallDict = @{
        @"internalUserID": [self internalUserID],
        @"appVersion": device.appVersion,
        @"device": @{
                    @"os": @{
                            @"name": device.osName,
                            @"version": device.osVersion,
                            @"manufacturer": device.manufacturer
                    },
                    @"ads": @{
                            // Need to replace with public method
                            @"trackingEnabled": @"1",
                            @"IDFA": device.advertiserID,
                    },
                    @"deviceId": device.vendorID,
                    @"model": device.model,
                    @"carrier": device.carrier,
                    @"locale": device.language,
                    @"country": device.country,
                    @"timezone": NSTimeZone.localTimeZone.name
            }
    };
    
    return overallDict.copy;
}

+ (void)saveInternalUserID:(nonnull NSString *)uid {
    [[NSUserDefaults standardUserDefaults] setObject:uid forKey:keyQInternalUserID];
}

+ (NSString *)internalUserID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:keyQInternalUserID] ?: @"";
}

@end
