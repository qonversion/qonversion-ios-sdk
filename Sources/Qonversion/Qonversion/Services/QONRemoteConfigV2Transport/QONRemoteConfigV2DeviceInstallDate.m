#import "QONRemoteConfigV2DeviceInstallDate.h"
#import "QNLocalStorage.h"
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NSString *const QONRemoteConfigV2DeviceInstallDateStorageKey =
    @"com.qonversion.keys.remote-config-v2-device-installed-at";

static NSInteger const QONRemoteConfigV2DeviceInstallDateSchema = 1;
/** Sanity ceiling for a plausible install second: year 5138. */
static int64_t const QONRemoteConfigV2DeviceInstallDateMaximumSeconds = 99999999999LL;

static BOOL QONRemoteConfigV2InstallDateExactInt64(id object, int64_t *value) {
  if (![object isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID()) return NO;
  const char type = [object objCType][0];
  if (strchr("csiql", type)) {
    if (value) *value = [object longLongValue];
    return YES;
  }
  if (strchr("CSILQ", type)) {
    unsigned long long candidate = [object unsignedLongLongValue];
    if (candidate > INT64_MAX) return NO;
    if (value) *value = (int64_t)candidate;
    return YES;
  }
  return NO;
}

static BOOL QONRemoteConfigV2InstallDateValidSeconds(int64_t seconds) {
  return seconds > 0 && seconds <= QONRemoteConfigV2DeviceInstallDateMaximumSeconds;
}

@interface QONRemoteConfigV2DeviceInstallDateProvider ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@property (nonatomic, strong, nullable) NSNumber *systemInstallDateSeconds;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchClock> clock;
@property (nonatomic, strong, nullable) NSNumber *cachedSeconds;
@end

@implementation QONRemoteConfigV2DeviceInstallDateProvider

+ (NSNumber *)installDateSecondsFromSystemFact:(NSString *)fact {
  if (![fact isKindOfClass:NSString.class] || fact.length == 0) return nil;

  // Only a bare run of digits is a date. `longLongValue` would happily read
  // "17 years" as 17, and a leading `-` as a pre-epoch install.
  NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
  if ([fact rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return nil;

  long long seconds = fact.longLongValue;
  return seconds > 0 ? @(seconds) : nil;
}

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
            systemInstallDateSeconds:(NSNumber *)systemInstallDateSeconds
                               clock:(id<QONRemoteConfigV2FetchClock>)clock {
  if (!localStorage || !clock) return nil;
  self = [super init];
  if (self) {
    _localStorage = localStorage;
    _systemInstallDateSeconds = systemInstallDateSeconds;
    _clock = clock;
  }
  return self;
}

- (nullable NSNumber *)deviceInstalledAtSeconds {
  @synchronized (self) {
    if (self.cachedSeconds) return self.cachedSeconds;

    NSNumber *stored = [self storedSeconds];
    if (stored) {
      self.cachedSeconds = stored;
      return stored;
    }

    NSNumber *seed = [self seedSeconds];
    if (!seed) return nil;

    [self persistSeconds:seed];
    // Cached even when persistence fails so the value stays stable for this process.
    self.cachedSeconds = seed;
    return seed;
  }
}

- (nullable NSNumber *)storedSeconds {
  id object = nil;
  @try {
    object = [self.localStorage loadObjectForKey:QONRemoteConfigV2DeviceInstallDateStorageKey];
  } @catch (__unused NSException *exception) {
    return nil;
  }
  if (![object isKindOfClass:NSDictionary.class]) return nil;

  NSDictionary *dictionary = object;
  int64_t schema = 0;
  int64_t seconds = 0;
  if (!QONRemoteConfigV2InstallDateExactInt64(dictionary[@"schema_version"], &schema) ||
      schema != QONRemoteConfigV2DeviceInstallDateSchema ||
      !QONRemoteConfigV2InstallDateExactInt64(dictionary[@"device_installed_at"], &seconds) ||
      !QONRemoteConfigV2InstallDateValidSeconds(seconds)) {
    return nil;
  }
  return @(seconds);
}

- (nullable NSNumber *)seedSeconds {
  int64_t system = 0;
  if (QONRemoteConfigV2InstallDateExactInt64(self.systemInstallDateSeconds, &system) &&
      QONRemoteConfigV2InstallDateValidSeconds(system)) {
    return @(system);
  }

  int64_t nowMilliseconds = 0;
  @try {
    nowMilliseconds = [self.clock nowMilliseconds];
  } @catch (__unused NSException *exception) {
    return nil;
  }
  int64_t seconds = nowMilliseconds / 1000;
  if (!QONRemoteConfigV2InstallDateValidSeconds(seconds)) return nil;
  return @(seconds);
}

- (void)persistSeconds:(NSNumber *)seconds {
  NSDictionary *payload = @{
    @"schema_version": @(QONRemoteConfigV2DeviceInstallDateSchema),
    @"device_installed_at": seconds,
  };
  @try {
    [self.localStorage storeObject:payload forKey:QONRemoteConfigV2DeviceInstallDateStorageKey];
  } @catch (__unused NSException *exception) {}
}

@end
