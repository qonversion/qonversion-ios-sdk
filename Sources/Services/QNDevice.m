#import "QNDevice.h"
#import "QNConstants.h"
#import <UIKit/UIKit.h>

#import <sys/sysctl.h>
#import <sys/types.h>

@implementation QNDevice {
  NSObject* networkInfo;
}


+ (instancetype)current {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = self.new;
  });
  
  return shared;
}

@synthesize model = _model;
@synthesize installDate = _installDate;
@synthesize osVersion = _osVersion;
@synthesize appVersion = _appVersion;
@synthesize carrier = _carrier;
@synthesize country = _country;
@synthesize language = _language;
@synthesize advertiserID = _advertiserID;
@synthesize vendorID = _vendorID;

- (NSString *)osName {
  return keyQOSName;
}

- (NSString *)appVersion {
  if (!_appVersion) {
    _appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
  }
  return _appVersion;
}

- (NSString *)osVersion {
  if (!_osVersion) {
    _osVersion = [[UIDevice currentDevice] systemVersion];
  }
  return _osVersion;
}

- (NSString *)manufacturer {
  return @"Apple";
}

- (NSString *)model {
  if (!_model) {
    _model = [QNDevice getDeviceModel];
  }
  return _model;
}

- (nullable NSString *)installDate {
  if (!_installDate) {
    NSURL *docsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if (docsURL) {
      NSDictionary *docsAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:docsURL.path error:nil];
      NSDate *date = docsAttributes.fileCreationDate;
      if (date) {
        _installDate = [NSString stringWithFormat:@"%ld", (long)round(date.timeIntervalSince1970)];
      }
    }
  }
  
  return _installDate;
}

- (NSString *)carrier {
  if (!_carrier) {
    Class CTTelephonyNetworkInfo = NSClassFromString(@"CTTelephonyNetworkInfo");
    SEL subscriberCellularProvider = NSSelectorFromString(@"subscriberCellularProvider");
    SEL carrierName = NSSelectorFromString(@"carrierName");
    if (CTTelephonyNetworkInfo && subscriberCellularProvider && carrierName) {
      networkInfo = [[NSClassFromString(@"CTTelephonyNetworkInfo") alloc] init];
      id carrier = nil;
      id (*imp1)(id, SEL) = (id (*)(id, SEL))[networkInfo methodForSelector:subscriberCellularProvider];
      if (imp1) {
        carrier = imp1(networkInfo, subscriberCellularProvider);
      }
      NSString* (*imp2)(id, SEL) = (NSString* (*)(id, SEL))[carrier methodForSelector:carrierName];
      if (imp2) {
        _carrier = imp2(carrier, carrierName);
      }
    }
    
    if (!_carrier) {
      _carrier = @"Unknown";
    }
  }
  return _carrier;
}

- (NSString *)country {
  if (!_country) {
    _country = [[NSLocale localeWithLocaleIdentifier:@"en_US"] displayNameForKey: NSLocaleCountryCode
                                                                           value: [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode]];
  }
  return _country;
}

- (NSString *)timezone {
  return NSTimeZone.localTimeZone.name;
}

- (NSString *)language {
  if (!_language) {
    _language = [[NSLocale localeWithLocaleIdentifier:@"en_US"] displayNameForKey: NSLocaleLanguageCode
                                                                            value: [[NSLocale preferredLanguages] objectAtIndex:0]];
  }
  return _language;
}

- (NSString *)advertiserID {
  if (!_advertiserID) {
    NSString *advertiserId = [QNDevice getAdvertiserID:5];
    if (advertiserId != nil &&
        ![advertiserId isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
      _advertiserID = advertiserId;
    }
  }
  return _advertiserID;
}

- (nullable NSString *)afUserID {
  Class AppsFlyerTracker = NSClassFromString(@"AppsFlyerTracker");
  SEL sharedTracker = NSSelectorFromString(@"sharedTracker");
  SEL getAppsFlyerUID = NSSelectorFromString(@"getAppsFlyerUID");
  if (AppsFlyerTracker && sharedTracker && getAppsFlyerUID) {
    id (*imp1)(id, SEL) = (id (*)(id, SEL))[AppsFlyerTracker methodForSelector:sharedTracker];
    id tracker = nil;
    NSString *appsFlyerUID = nil;
    if (imp1) {
      tracker = imp1(AppsFlyerTracker, sharedTracker);
    }
    
    NSString* (*imp2)(id, SEL) = (NSString* (*)(id, SEL))[tracker methodForSelector:getAppsFlyerUID];
    if (imp2) {
      appsFlyerUID = imp2(tracker, getAppsFlyerUID);
    }
    
    return appsFlyerUID;
  }
  
  return nil;
}

- (nullable NSString *)fbAnonID {
  NSString *advertiserId = [QNDevice getAdvertiserID:2];
  
  if (advertiserId && ![advertiserId isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
    return nil;
  } else {
    Class FBSDKAppEvents = NSClassFromString(@"FBSDKAppEvents");
    SEL anonymousID = NSSelectorFromString(@"anonymousID");
    if (FBSDKAppEvents && anonymousID) {
      id (*imp1)(id, SEL) = (id (*)(id, SEL))[FBSDKAppEvents methodForSelector:anonymousID];
      NSString *anonID = nil;
      if (imp1 && [FBSDKAppEvents respondsToSelector:anonymousID]) {
        anonID = imp1(FBSDKAppEvents, anonymousID);
      }
      
      if (anonID) {
        return anonID;
      }
    }
    
    Class FBSDKBasicUtility = NSClassFromString(@"FBSDKBasicUtility");
    SEL FBSDKBasicUtilityanonymousID = NSSelectorFromString(@"anonymousID");
    
    if (FBSDKBasicUtility && FBSDKBasicUtilityanonymousID) {
      id (*imp1)(id, SEL) = (id (*)(id, SEL))[FBSDKBasicUtility methodForSelector:FBSDKBasicUtilityanonymousID];
      NSString *anonID = nil;
      if (imp1) {
        anonID = imp1(FBSDKBasicUtility, FBSDKBasicUtilityanonymousID);
      }
      
      if (anonID) {
        return anonID;
      }
    }
  }
  
  return nil;
}

- (nullable NSString *)adjustUserID {
  Class Adjust = NSClassFromString(@"Adjust");
  SEL adid = NSSelectorFromString(@"adid");
  if (Adjust && adid) {
    id (*imp1)(id, SEL) = (id (*)(id, SEL))[Adjust methodForSelector:adid];
    NSString *adidString = nil;
    if (imp1) {
      adidString = imp1(Adjust, adid);
    }
    
    return adidString;
  }
  
  return nil;
}

- (NSString *)vendorID {
  if (!_vendorID) {
    NSString *identifierForVendor = [QNDevice getVendorID:5];
    if (identifierForVendor != nil &&
        ![identifierForVendor isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
      _vendorID = identifierForVendor;
    }
  }
  return _vendorID;
}

+ (NSString*)getAdvertiserID:(int) maxAttempts {
  Class ASIdentifierManager = NSClassFromString(@"ASIdentifierManager");
  SEL sharedManager = NSSelectorFromString(@"sharedManager");
  SEL advertisingIdentifier = NSSelectorFromString(@"advertisingIdentifier");
  if (ASIdentifierManager && sharedManager && advertisingIdentifier) {
    id (*imp1)(id, SEL) = (id (*)(id, SEL))[ASIdentifierManager methodForSelector:sharedManager];
    id manager = nil;
    NSUUID *adid = nil;
    NSString *identifier = nil;
    if (imp1) {
      manager = imp1(ASIdentifierManager, sharedManager);
    }
    NSUUID* (*imp2)(id, SEL) = (NSUUID* (*)(id, SEL))[manager methodForSelector:advertisingIdentifier];
    if (imp2) {
      adid = imp2(manager, advertisingIdentifier);
    }
    if (adid) {
      identifier = [adid UUIDString];
    }
    if (identifier == nil && maxAttempts > 0) {
      // Try again every 5 seconds
      [NSThread sleepForTimeInterval:5.0];
      return [QNDevice getAdvertiserID:maxAttempts - 1];
    } else {
      return identifier;
    }
  } else {
    return nil;
  }
}

+ (NSString*)getVendorID:(int) maxAttempts {
  NSString *identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
  if (identifier == nil && maxAttempts > 0) {
    // Try again every 5 seconds
    [NSThread sleepForTimeInterval:5.0];
    return [QNDevice getVendorID:maxAttempts - 1];
  } else {
    return identifier;
  }
}

+ (NSString*)getPlatformString {
#if !TARGET_OS_OSX
  const char *sysctl_name = "hw.machine";
#else
  const char *sysctl_name = "hw.model";
#endif
  size_t size;
  sysctlbyname(sysctl_name, NULL, &size, NULL, 0);
  char *machine = malloc(size);
  sysctlbyname(sysctl_name, machine, &size, NULL, 0);
  NSString *platform = [NSString stringWithUTF8String:machine];
  free(machine);
  return platform;
}

+ (NSString*)getDeviceModel {
  NSString *platform = [self getPlatformString];
  // == iPhone ==
  // iPhone 1
  if ([platform isEqualToString:@"iPhone1,1"])    return @"iPhone 1";
  // iPhone 3
  if ([platform isEqualToString:@"iPhone1,2"])    return @"iPhone 3G";
  if ([platform isEqualToString:@"iPhone2,1"])    return @"iPhone 3GS";
  // iPhone 4
  if ([platform isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
  if ([platform isEqualToString:@"iPhone3,2"])    return @"iPhone 4";
  if ([platform isEqualToString:@"iPhone3,3"])    return @"iPhone 4";
  if ([platform isEqualToString:@"iPhone4,1"])    return @"iPhone 4S";
  // iPhone 5
  if ([platform isEqualToString:@"iPhone5,1"])    return @"iPhone 5";
  if ([platform isEqualToString:@"iPhone5,2"])    return @"iPhone 5";
  if ([platform isEqualToString:@"iPhone5,3"])    return @"iPhone 5c";
  if ([platform isEqualToString:@"iPhone5,4"])    return @"iPhone 5c";
  if ([platform isEqualToString:@"iPhone6,1"])    return @"iPhone 5s";
  if ([platform isEqualToString:@"iPhone6,2"])    return @"iPhone 5s";
  // iPhone 6
  if ([platform isEqualToString:@"iPhone7,1"])    return @"iPhone 6 Plus";
  if ([platform isEqualToString:@"iPhone7,2"])    return @"iPhone 6";
  if ([platform isEqualToString:@"iPhone8,1"])    return @"iPhone 6s";
  if ([platform isEqualToString:@"iPhone8,2"])    return @"iPhone 6s Plus";
  if ([platform isEqualToString:@"iPhone8,4"])    return @"iPhone SE";
  // iPhone 7
  if ([platform isEqualToString:@"iPhone9,1"])    return @"iPhone 7";
  if ([platform isEqualToString:@"iPhone9,2"])    return @"iPhone 7 Plus";
  if ([platform isEqualToString:@"iPhone9,3"])    return @"iPhone 7";
  if ([platform isEqualToString:@"iPhone9,4"])    return @"iPhone 7 Plus";
  // iPhone 8
  if ([platform isEqualToString:@"iPhone10,1"])    return @"iPhone 8";
  if ([platform isEqualToString:@"iPhone10,4"])    return @"iPhone 8";
  if ([platform isEqualToString:@"iPhone10,2"])    return @"iPhone 8 Plus";
  if ([platform isEqualToString:@"iPhone10,5"])    return @"iPhone 8 Plus";
  
  // iPhone X
  if ([platform isEqualToString:@"iPhone10,3"])    return @"iPhone X";
  if ([platform isEqualToString:@"iPhone10,6"])    return @"iPhone X";
  
  // iPhone XS
  if ([platform isEqualToString:@"iPhone11,2"])    return @"iPhone XS";
  if ([platform isEqualToString:@"iPhone11,6"])    return @"iPhone XS Max";
  
  // iPhone XR
  if ([platform isEqualToString:@"iPhone11,8"])    return @"iPhone XR";
  
  // iPhone 11
  if ([platform isEqualToString:@"iPhone12,1"])    return @"iPhone 11";
  if ([platform isEqualToString:@"iPhone12,3"])    return @"iPhone 11 Pro";
  if ([platform isEqualToString:@"iPhone12,5"])    return @"iPhone 11 Pro Max";
  
  // == iPod ==
  if ([platform isEqualToString:@"iPod1,1"])      return @"iPod Touch 1G";
  if ([platform isEqualToString:@"iPod2,1"])      return @"iPod Touch 2G";
  if ([platform isEqualToString:@"iPod3,1"])      return @"iPod Touch 3G";
  if ([platform isEqualToString:@"iPod4,1"])      return @"iPod Touch 4G";
  if ([platform isEqualToString:@"iPod5,1"])      return @"iPod Touch 5G";
  if ([platform isEqualToString:@"iPod7,1"])      return @"iPod Touch 6G";
  if ([platform isEqualToString:@"iPod9,1"])      return @"iPod Touch 7G";
  
  // == iPad ==
  // iPad 1
  if ([platform isEqualToString:@"iPad1,1"])      return @"iPad 1";
  // iPad 2
  if ([platform isEqualToString:@"iPad2,1"])      return @"iPad 2";
  if ([platform isEqualToString:@"iPad2,2"])      return @"iPad 2";
  if ([platform isEqualToString:@"iPad2,3"])      return @"iPad 2";
  if ([platform isEqualToString:@"iPad2,4"])      return @"iPad 2";
  // iPad 3
  if ([platform isEqualToString:@"iPad3,1"])      return @"iPad 3";
  if ([platform isEqualToString:@"iPad3,2"])      return @"iPad 3";
  if ([platform isEqualToString:@"iPad3,3"])      return @"iPad 3";
  // iPad 4
  if ([platform isEqualToString:@"iPad3,4"])      return @"iPad 4";
  if ([platform isEqualToString:@"iPad3,5"])      return @"iPad 4";
  if ([platform isEqualToString:@"iPad3,6"])      return @"iPad 4";
  // iPad Air
  if ([platform isEqualToString:@"iPad4,1"])      return @"iPad Air";
  if ([platform isEqualToString:@"iPad4,2"])      return @"iPad Air";
  if ([platform isEqualToString:@"iPad4,3"])      return @"iPad Air";
  // iPad Air 2
  if ([platform isEqualToString:@"iPad5,3"])      return @"iPad Air 2";
  if ([platform isEqualToString:@"iPad5,4"])      return @"iPad Air 2";
  // iPad 5
  if ([platform isEqualToString:@"iPad6,11"])      return @"iPad 5";
  if ([platform isEqualToString:@"iPad6,12"])      return @"iPad 5";
  // iPad 6
  if ([platform isEqualToString:@"iPad7,5"])      return @"iPad 6";
  if ([platform isEqualToString:@"iPad7,6"])      return @"iPad 6";
  // iPad Air 3
  if ([platform isEqualToString:@"iPad11,3"])      return @"iPad Air 3";
  if ([platform isEqualToString:@"iPad11,4"])      return @"iPad Air 3";
  // iPad 7
  if ([platform isEqualToString:@"iPad7,11"])      return @"iPad 6";
  if ([platform isEqualToString:@"iPad7,12"])      return @"iPad 6";
  
  // iPad Pro
  if ([platform isEqualToString:@"iPad6,7"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad6,8"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad6,3"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad6,4"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad7,1"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad7,2"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad7,3"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad7,4"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,1"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,2"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,3"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,4"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,5"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,6"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,7"])      return @"iPad Pro";
  if ([platform isEqualToString:@"iPad8,8"])      return @"iPad Pro";
  
  // iPad Mini
  if ([platform isEqualToString:@"iPad2,5"])      return @"iPad Mini";
  if ([platform isEqualToString:@"iPad2,6"])      return @"iPad Mini";
  if ([platform isEqualToString:@"iPad2,7"])      return @"iPad Mini";
  // iPad Mini 2
  if ([platform isEqualToString:@"iPad4,4"])      return @"iPad Mini 2";
  if ([platform isEqualToString:@"iPad4,5"])      return @"iPad Mini 2";
  if ([platform isEqualToString:@"iPad4,6"])      return @"iPad Mini 2";
  // iPad Mini 3
  if ([platform isEqualToString:@"iPad4,7"])      return @"iPad Mini 3";
  if ([platform isEqualToString:@"iPad4,8"])      return @"iPad Mini 3";
  if ([platform isEqualToString:@"iPad4,9"])      return @"iPad Mini 3";
  // iPad Mini 4
  if ([platform isEqualToString:@"iPad5,1"])      return @"iPad Mini 4";
  if ([platform isEqualToString:@"iPad5,2"])      return @"iPad Mini 4";
  // iPad Mini 5
  if ([platform isEqualToString:@"iPad11,1"])      return @"iPad Mini 5";
  if ([platform isEqualToString:@"iPad11,2"])      return @"iPad Mini 5";
  
  // == Others ==
  if ([platform isEqualToString:@"i386"])         return @"Simulator";
  if ([platform isEqualToString:@"x86_64"])       return @"Simulator";
  if ([platform hasPrefix:@"MacBookAir"])         return @"MacBook Air";
  if ([platform hasPrefix:@"MacBookPro"])         return @"MacBook Pro";
  if ([platform hasPrefix:@"MacBook"])            return @"MacBook";
  if ([platform hasPrefix:@"MacPro"])             return @"Mac Pro";
  if ([platform hasPrefix:@"Macmini"])            return @"Mac Mini";
  if ([platform hasPrefix:@"iMac"])               return @"iMac";
  if ([platform hasPrefix:@"Xserve"])             return @"Xserve";
  return platform;
}
@end
