#import "QONRemoteConfigV2ContextPinStore.h"
#import "QNLocalStorage.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

static NSInteger const QONRemoteConfigV2ContextPinSchema = 1;
static NSString *const QONRemoteConfigV2ContextPinPrefix =
    @"com.qonversion.keys.remote-config-v2-context-pin.";
static NSString *const QONRemoteConfigV2ContextPinDomain = @"remote-config-v2-context-pin-v1";

static BOOL QONRemoteConfigV2ContextPinExactInt64(id object, int64_t *value) {
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

static void QONRemoteConfigV2ContextPinAppendFramed(NSMutableData *data, NSData *value) {
  uint32_t length = CFSwapInt32HostToBig((uint32_t)value.length);
  [data appendBytes:&length length:sizeof(length)];
  [data appendData:value];
}

static NSString *QONRemoteConfigV2ContextPinSHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return [hex copy];
}

@interface QONRemoteConfigV2ContextPinStore ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@end

@implementation QONRemoteConfigV2ContextPinStore

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  if (!localStorage) return nil;
  self = [super init];
  if (self) _localStorage = localStorage;
  return self;
}

+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2ContextPinAppendFramed(framing,
      [QONRemoteConfigV2ContextPinDomain dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2ContextPinAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2ContextPinAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2ContextPinAppendFramed(framing,
      [scope.canonicalUserID dataUsingEncoding:NSUTF8StringEncoding]);
  return [QONRemoteConfigV2ContextPinPrefix
      stringByAppendingString:QONRemoteConfigV2ContextPinSHA256(framing)];
}

- (nullable NSString *)contextFingerprintForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return nil;
  NSString *key = [QONRemoteConfigV2ContextPinStore storageKeyForScope:scope];
  @synchronized (self) {
    id object = nil;
    @try {
      object = [self.localStorage loadObjectForKey:key];
    } @catch (__unused NSException *exception) {
      return nil;
    }
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dictionary = object;
    int64_t schema = 0;
    if (!QONRemoteConfigV2ContextPinExactInt64(dictionary[@"schema_version"], &schema) ||
        schema != QONRemoteConfigV2ContextPinSchema ||
        ![dictionary[@"scope_key"] isKindOfClass:NSString.class] ||
        ![dictionary[@"scope_key"] isEqualToString:key] ||
        !QONRemoteConfigV2ValidContextFingerprint(dictionary[@"context_fingerprint"])) {
      return nil;
    }
    return [dictionary[@"context_fingerprint"] copy];
  }
}

- (BOOL)storeContextFingerprint:(NSString *)contextFingerprint
                       forScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope || !QONRemoteConfigV2ValidContextFingerprint(contextFingerprint)) return NO;
  NSString *key = [QONRemoteConfigV2ContextPinStore storageKeyForScope:scope];
  NSDictionary *payload = @{
    @"schema_version": @(QONRemoteConfigV2ContextPinSchema),
    @"scope_key": key,
    @"context_fingerprint": [contextFingerprint copy],
  };
  @synchronized (self) {
    @try {
      [self.localStorage storeObject:payload forKey:key];
      id readBack = [self.localStorage loadObjectForKey:key];
      return [readBack isEqual:payload];
    } @catch (__unused NSException *exception) {
      return NO;
    }
  }
}

- (void)removeContextFingerprintForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return;
  @synchronized (self) {
    @try {
      [self.localStorage
          removeObjectForKey:[QONRemoteConfigV2ContextPinStore storageKeyForScope:scope]];
    } @catch (__unused NSException *exception) {}
  }
}

@end
