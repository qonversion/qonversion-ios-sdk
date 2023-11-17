#import "QNInternalConstants.h"
#import "QNDevice.h"

#import "QNUserInfo.h"

@implementation QNUserInfo

+ (NSDictionary *)overallData {
  QNDevice *device = QNDevice.current;
  NSMutableDictionary *overallDict = [NSMutableDictionary new];
  
  NSString *installDate = device.installDate;
  if (installDate) {
    [overallDict setValue:installDate forKey:@"install_date"];
  }
  
  if ([QNUserInfo appStoreReceipt]) {
    [overallDict setValue:[QNUserInfo appStoreReceipt] forKey:@"receipt"];
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
  NSURL *receiptURL = QNUserInfo.bundle.appStoreReceiptURL;
  
  if (!receiptURL) {
    return @"";
  }
  
  NSString *receipt = [[NSData dataWithContentsOfURL:receiptURL] base64EncodedStringWithOptions:0];
  
  return receipt ?: @"";
}

+ (BOOL)isDebug {
  NSURL *receiptURL = QNUserInfo.bundle.appStoreReceiptURL;
  
  if (!receiptURL) {
    return NO;
  }
  
  return ([receiptURL.path rangeOfString:@"sandboxReceipt"].location != NSNotFound);
}

+ (nullable NSBundle *)bundle {
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"appStoreReceiptURL != nil"];
  return [NSBundle.allBundles filteredArrayUsingPredicate:predicate].firstObject;
}

@end
