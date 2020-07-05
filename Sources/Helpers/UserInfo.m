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
  
  [overallDict setObject:keyQVersion forKey:@"version"];
  
  NSString *installDate = device.installDate;
  if (installDate) {
    [overallDict setValue:installDate forKey:@"install_date"];
  }
  
  if ([self internalUserID]) {
    [overallDict setValue:[self internalUserID] forKey:@"custom_uid"];
  }
  
  if ([UserInfo appStoreReceipt]) {
    [overallDict setValue:[UserInfo appStoreReceipt] forKey:@"receipt"];
  }
  
  NSMutableDictionary *deviceDict = [NSMutableDictionary new];
  
  if (device.osName) {
    [deviceDict setValue:device.osName forKey:@"os"];
  }
  
  if (device.osVersion) {
    [deviceDict setValue:device.osVersion forKey:@"os_version"];
  }
  
  if (device.manufacturer) {
    [deviceDict setValue:device.manufacturer forKey:@"manufacturer"];
  }
  
  // Need to replace with public method
  [deviceDict setValue:@"1" forKey:@"tracking_enabled"];
  
  if (device.advertiserID) {
    [deviceDict setValue:device.advertiserID forKey:@"advertiser_id"];
  }
  
  if (device.appVersion) {
    [deviceDict setValue:device.appVersion forKey:@"app_version"];
  }
  
  if (device.vendorID) {
    [deviceDict setValue:device.vendorID forKey:@"device_id"];
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
