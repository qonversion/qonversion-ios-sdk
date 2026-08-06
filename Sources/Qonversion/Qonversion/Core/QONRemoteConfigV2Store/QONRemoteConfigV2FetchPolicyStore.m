#import "QONRemoteConfigV2FetchPolicyStore.h"
#import "QNLocalStorage.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NSUInteger const QONRemoteConfigV2FetchPolicyMaximumArchiveBytes = 2048;
static NSInteger const QONRemoteConfigV2FetchPolicySchema = 1;
static NSString *const QONRemoteConfigV2FetchPolicyPrefix =
    @"com.qonversion.keys.remote-config-v2-fetch-policy.";

static BOOL QONRemoteConfigV2FetchPolicyExactInt64(id object, int64_t *value) {
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

static void QONRemoteConfigV2FetchPolicyAppendFramed(NSMutableData *data, NSData *value) {
  uint32_t length = CFSwapInt32HostToBig((uint32_t)value.length);
  [data appendBytes:&length length:sizeof(length)];
  [data appendData:value];
}

static void QONRemoteConfigV2FetchPolicyAppendInt64(NSMutableData *data, int64_t value) {
  uint64_t encoded = CFSwapInt64HostToBig((uint64_t)value);
  [data appendBytes:&encoded length:sizeof(encoded)];
}

static NSString *QONRemoteConfigV2FetchPolicySHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return hex;
}

static NSString *QONRemoteConfigV2FetchPolicyStorageKey(QONRemoteConfigV2FetchPolicyScope *scope) {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2FetchPolicyAppendFramed(framing,
      [@"remote-config-fetch-policy-v1" dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2FetchPolicyAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2FetchPolicyAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  return [QONRemoteConfigV2FetchPolicyPrefix
      stringByAppendingString:QONRemoteConfigV2FetchPolicySHA256(framing)];
}

static NSString *QONRemoteConfigV2FetchPolicyIntegrityDigest(
    QONRemoteConfigV2FetchPolicyScope *scope, QONRemoteConfigV2FetchPolicyState *state) {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2FetchPolicyAppendFramed(framing,
      [@"remote-config-fetch-policy-state-v1" dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2FetchPolicyAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2FetchPolicyAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2FetchPolicyAppendInt64(framing, QONRemoteConfigV2FetchPolicySchema);
  QONRemoteConfigV2FetchPolicyAppendInt64(framing, state.lastSuccessfulFetchAtMilliseconds);
  QONRemoteConfigV2FetchPolicyAppendInt64(framing, state.consecutiveRetryableFailures);
  QONRemoteConfigV2FetchPolicyAppendInt64(framing, state.nextAllowedFetchAtMilliseconds);
  return QONRemoteConfigV2FetchPolicySHA256(framing);
}

@interface QONRemoteConfigV2FetchPolicyStore ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@end

@implementation QONRemoteConfigV2FetchPolicyStore

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  if (!localStorage) return nil;
  self = [super init];
  if (self) _localStorage = localStorage;
  return self;
}

- (NSDictionary *)dictionaryForState:(QONRemoteConfigV2FetchPolicyState *)state
                                scope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  return @{
    @"schema_version": @(QONRemoteConfigV2FetchPolicySchema),
    @"project": scope.projectKey,
    @"environment": scope.environment,
    @"last_successful_fetch_at_ms": @(state.lastSuccessfulFetchAtMilliseconds),
    @"consecutive_retryable_failures": @(state.consecutiveRetryableFailures),
    @"next_allowed_fetch_at_ms": @(state.nextAllowedFetchAtMilliseconds),
    @"integrity_digest": QONRemoteConfigV2FetchPolicyIntegrityDigest(scope, state),
  };
}

- (BOOL)objectFitsArchiveBudget:(id)object {
  @try {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:object
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    return data.length > 0 && data.length <= QONRemoteConfigV2FetchPolicyMaximumArchiveBytes && !error;
  } @catch (__unused NSException *exception) {
    return NO;
  }
}

- (QONRemoteConfigV2FetchPolicyLoadResult *)loadResultForScope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  if (!scope) {
    return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
        initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusFailed state:nil];
  }
  @synchronized (self) {
    NSString *key = QONRemoteConfigV2FetchPolicyStorageKey(scope);
    id object = nil;
    @try { object = [self.localStorage loadObjectForKey:key]; }
    @catch (__unused NSException *exception) {
      return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
          initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusFailed state:nil];
    }
    if (!object) {
      return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
          initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusMissing state:nil];
    }
    if (![object isKindOfClass:NSDictionary.class] || ![self objectFitsArchiveBudget:object]) {
      return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
          initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusCorrupt state:nil];
    }
    @try {
      NSDictionary *dictionary = object;
      if (dictionary.count != 7 || ![dictionary[@"project"] isKindOfClass:NSString.class] ||
          ![dictionary[@"environment"] isKindOfClass:NSString.class] ||
          ![dictionary[@"integrity_digest"] isKindOfClass:NSString.class] ||
          ![dictionary[@"project"] isEqualToString:scope.projectKey] ||
          ![dictionary[@"environment"] isEqualToString:scope.environment]) {
        return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
            initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusCorrupt state:nil];
      }
      int64_t schema = 0, lastSuccessful = 0, failures = 0, nextAllowed = 0;
      if (!QONRemoteConfigV2FetchPolicyExactInt64(dictionary[@"schema_version"], &schema) ||
          !QONRemoteConfigV2FetchPolicyExactInt64(dictionary[@"last_successful_fetch_at_ms"],
                                                  &lastSuccessful) ||
          !QONRemoteConfigV2FetchPolicyExactInt64(dictionary[@"consecutive_retryable_failures"],
                                                  &failures) ||
          !QONRemoteConfigV2FetchPolicyExactInt64(dictionary[@"next_allowed_fetch_at_ms"],
                                                  &nextAllowed) ||
          schema != QONRemoteConfigV2FetchPolicySchema || lastSuccessful < 0 ||
          failures < 0 || failures > 63 || nextAllowed < 0) {
        return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
            initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusCorrupt state:nil];
      }
      QONRemoteConfigV2FetchPolicyState *state = [[QONRemoteConfigV2FetchPolicyState alloc]
          initWithLastSuccessfulFetchAtMilliseconds:lastSuccessful
          consecutiveRetryableFailures:(NSInteger)failures
          nextAllowedFetchAtMilliseconds:nextAllowed];
      if (!state || ![dictionary[@"integrity_digest"] isEqualToString:
          QONRemoteConfigV2FetchPolicyIntegrityDigest(scope, state)]) {
        return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
            initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusCorrupt state:nil];
      }
      return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
          initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusFound state:state];
    } @catch (__unused NSException *exception) {
      return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
          initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusCorrupt state:nil];
    }
  }
}

- (BOOL)saveState:(QONRemoteConfigV2FetchPolicyState *)state
          forScope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  if (!state || !scope) return NO;
  NSDictionary *dictionary = [self dictionaryForState:state scope:scope];
  if (![self objectFitsArchiveBudget:dictionary]) return NO;
  @synchronized (self) {
    NSString *key = QONRemoteConfigV2FetchPolicyStorageKey(scope);
    id previous = nil;
    BOOL attempted = NO;
    @try {
      previous = [self.localStorage loadObjectForKey:key];
      attempted = YES;
      [self.localStorage storeObject:dictionary forKey:key];
      id readBack = [self.localStorage loadObjectForKey:key];
      if ([readBack isEqual:dictionary]) return YES;
    } @catch (__unused NSException *exception) {}
    if (attempted) {
      @try {
        if (previous) [self.localStorage storeObject:previous forKey:key];
        else [self.localStorage removeObjectForKey:key];
      } @catch (__unused NSException *exception) {}
    }
    return NO;
  }
}

@end
