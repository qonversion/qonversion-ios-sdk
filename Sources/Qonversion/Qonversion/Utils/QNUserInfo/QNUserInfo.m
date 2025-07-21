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
  
  NSString *receipt = [QNUserInfo appStoreReceipt];
  if (receipt) {
    [overallDict setValue:receipt forKey:@"receipt"];
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

+ (NSString *)appStoreReceipt {
  NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
  if (!receiptURL) {
    return nil;
  }
  
  NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
  if (!receiptData) {
    return nil;
  }
  
  return [receiptData base64EncodedStringWithOptions:0];
}

+ (BOOL)isDebug {
  #ifdef DEBUG
    return YES;
  #else
    return NO;
  #endif
}

+ (NSBundle *)bundle {
  return [NSBundle mainBundle];
}

@end
