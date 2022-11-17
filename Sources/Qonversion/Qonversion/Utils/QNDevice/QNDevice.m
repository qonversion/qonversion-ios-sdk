#import "QNDevice.h"
#import "QNInternalConstants.h"
#import "QNUserDefaultsStorage.h"
#import "QNLocalStorage.h"
#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#import <net/if.h>
#import <net/if_dl.h>
#endif


#import <sys/sysctl.h>
#import <sys/types.h>

static NSString * const kUserDefaultsSuiteName = @"qonversion.device.suite";
static NSString * const kPushTokenKey = @"pushToken";
static NSString * const kPushTokenProcessedKey = @"pushTokenProcessed";

@interface QNDevice ()

@property (readwrite, copy, nonatomic) NSString *pushNotificationsToken;
@property (strong, nonatomic) id<QNLocalStorage> persistentStorage;
@property (assign, nonatomic) BOOL idfaProhibited;

@end

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

- (instancetype)init {
  self = [super init];
  if (self) {
    QNUserDefaultsStorage *storage = [QNUserDefaultsStorage new];
    storage.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kUserDefaultsSuiteName];
    _persistentStorage = storage;
    
    NSString *token = [_persistentStorage loadObjectForKey:kPushTokenKey];
    _pushNotificationsToken = [token isKindOfClass:[NSString class]] ? token : nil;
    _idfaProhibited = NO;
  }
  
  return self;
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
  return kQNPlatform;
}

- (NSString *)appVersion {
  if (!_appVersion) {
    _appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
  }
  return _appVersion;
}

- (NSString *)osVersion {
  if (!_osVersion) {
  #if UI_DEVICE
    _osVersion = [[UIDevice currentDevice] systemVersion];
  #else
    NSOperatingSystemVersion systemVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    _osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld",
                  (long)systemVersion.majorVersion,
                  (long)systemVersion.minorVersion,
                  (long)systemVersion.patchVersion];
  #endif
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

- (void)setPushNotificationsToken:(NSString *)token {
  _pushNotificationsToken = token;
  [self.persistentStorage storeObject:token forKey:kPushTokenKey];
}

- (BOOL)isPushTokenProcessed {
  return [self.persistentStorage loadBoolforKey:kPushTokenProcessedKey];
}

- (void)setPushTokenProcessed:(BOOL)processed {
  [self.persistentStorage storeBool:processed forKey:kPushTokenProcessedKey];
}

- (NSString *)advertiserID {
  if (!_advertiserID && !self.idfaProhibited) {
    SEL selector = NSSelectorFromString(@"obtainAdvertisingID");
    if ([[QNDevice current] respondsToSelector:selector]) {
      _advertiserID = ((NSString * (*)(id, SEL))[[QNDevice current] methodForSelector:selector])([QNDevice current], selector);
    } else {
      self.idfaProhibited = YES;
    }
  }
  
  return _advertiserID;
}

- (nullable NSString *)afUserID {
  return [self af5UserID] ?: [self af6UserID];
}

- (nullable NSString *)af5UserID {
  Class AppsFlyerTracker = NSClassFromString(@"AppsFlyerTracker");
  SEL sharedTracker = NSSelectorFromString(@"sharedTracker");
  SEL getAppsFlyerUID = NSSelectorFromString(@"getAppsFlyerUID");
  if (AppsFlyerTracker && sharedTracker && getAppsFlyerUID) {
    id (*imp1)(id, SEL) = (id (*)(id, SEL))[AppsFlyerTracker methodForSelector:sharedTracker];
    id tracker = nil;
    NSString *appsFlyerUID = nil;
    if (imp1 && [AppsFlyerTracker respondsToSelector:sharedTracker]) {
      tracker = imp1(AppsFlyerTracker, sharedTracker);
    }
    
    NSString* (*imp2)(id, SEL) = (NSString* (*)(id, SEL))[tracker methodForSelector:getAppsFlyerUID];
    if (imp2 && [tracker respondsToSelector:getAppsFlyerUID]) {
      appsFlyerUID = imp2(tracker, getAppsFlyerUID);
    }
    
    return appsFlyerUID;
  }
  
  return nil;
}

- (nullable NSString *)af6UserID {
  Class AppsFlyerTracker = NSClassFromString(@"AppsFlyerLib");
  SEL sharedTracker = NSSelectorFromString(@"shared");
  SEL getAppsFlyerUID = NSSelectorFromString(@"getAppsFlyerUID");
  if (AppsFlyerTracker && sharedTracker && getAppsFlyerUID) {
    id (*imp1)(id, SEL) = (id (*)(id, SEL))[AppsFlyerTracker methodForSelector:sharedTracker];
    id tracker = nil;
    NSString *appsFlyerUID = nil;
    if (imp1 && [AppsFlyerTracker respondsToSelector:sharedTracker]) {
      tracker = imp1(AppsFlyerTracker, sharedTracker);
    }
    
    NSString* (*imp2)(id, SEL) = (NSString* (*)(id, SEL))[tracker methodForSelector:getAppsFlyerUID];
    if (imp2 && [tracker respondsToSelector:getAppsFlyerUID]) {
      appsFlyerUID = imp2(tracker, getAppsFlyerUID);
    }
    
    return appsFlyerUID;
  }
  
  return nil;
}

- (nullable NSString *)fbAnonID {
  if (self.advertiserID && ![self.advertiserID isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
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
      if (imp1 && [FBSDKBasicUtility respondsToSelector:FBSDKBasicUtilityanonymousID]) {
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

+ (NSString*)getVendorID:(int) maxAttempts {
  NSString *identifier = nil;
  #if UI_DEVICE
      identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
  #elif TARGET_OS_OSX
      identifier = [self getMacAddress];
  #else
    identifier = @"";
  #endif
  
  if (identifier == nil && maxAttempts > 0) {
    // Try again every 5 seconds
    [NSThread sleepForTimeInterval:5.0];
    return [QNDevice getVendorID:maxAttempts - 1];
  } else {
    return identifier;
  }
}

+ (NSString*)getPlatformString {
#if UI_DEVICE
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
  return platform;
}

#if TARGET_OS_OSX
+ (NSString *)getMacAddress {
    int                 mgmtInfoBase[6];
    char                *msgBuffer = NULL;
    size_t              length;
    unsigned char       macAddress[6];
    struct if_msghdr    *interfaceMsgStruct;
    struct sockaddr_dl  *socketStruct;
    NSString            *errorFlag = NULL;
    bool                msgBufferAllocated = false;

    // Setup the management Information Base (mib)
    mgmtInfoBase[0] = CTL_NET;        // Request network subsystem
    mgmtInfoBase[1] = AF_ROUTE;       // Routing table info
    mgmtInfoBase[2] = 0;
    mgmtInfoBase[3] = AF_LINK;        // Request link layer information
    mgmtInfoBase[4] = NET_RT_IFLIST;  // Request all configured interfaces

    // With all configured interfaces requested, get handle index
    if ((mgmtInfoBase[5] = if_nametoindex("en0")) == 0) {
        errorFlag = @"if_nametoindex failure";
    } else {
        // Get the size of the data available (store in len)
        if (sysctl(mgmtInfoBase, 6, NULL, &length, NULL, 0) < 0) {
            errorFlag = @"sysctl mgmtInfoBase failure";
        } else {
            // Alloc memory based on above call
            if ((msgBuffer = malloc(length)) == NULL) {
                errorFlag = @"buffer allocation failure";
            } else {
                msgBufferAllocated = true;
                // Get system information, store in buffer
                if (sysctl(mgmtInfoBase, 6, msgBuffer, &length, NULL, 0) < 0) {
                    errorFlag = @"sysctl msgBuffer failure";
                }
            }
        }
    }

    // Before going any further...
    if (errorFlag != NULL) {
        NSLog(@"Cannot detect mac address. Error: %@", errorFlag);
        if (msgBufferAllocated) {
            free(msgBuffer);
        }
        return nil;
    }

    // Map msgbuffer to interface message structure
    interfaceMsgStruct = (struct if_msghdr *) msgBuffer;

    // Map to link-level socket structure
    socketStruct = (struct sockaddr_dl *) (interfaceMsgStruct + 1);

    // Copy link layer address data in socket structure to an array
    memcpy(&macAddress, socketStruct->sdl_data + socketStruct->sdl_nlen, 6);

    // Read from char array into a string object, into traditional Mac address format
    NSString *macAddressString = [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X",
                                  macAddress[0], macAddress[1], macAddress[2],
                                  macAddress[3], macAddress[4], macAddress[5]];

    // Release the buffer memory
    free(msgBuffer);

    return macAddressString;
}
#endif

@end
