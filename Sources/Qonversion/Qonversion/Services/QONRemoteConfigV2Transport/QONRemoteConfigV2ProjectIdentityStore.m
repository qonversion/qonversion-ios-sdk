#import "QONRemoteConfigV2ProjectIdentityStore.h"
#import "QNLocalStorage.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

static NSInteger const QONRemoteConfigV2ProjectIdentitySchema = 1;
static NSString *const QONRemoteConfigV2ProjectIdentityPrefix =
    @"com.qonversion.keys.remote-config-v2-project-identity.";

static BOOL QONRemoteConfigV2IdentityExactInt64(id object, int64_t *value) {
  if (![object isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID()) return NO;
  const char type = [object objCType][0];
  // strchr matches the terminator, so an empty type encoding must not read as signed.
  if (type && strchr("csiql", type)) {
    if (value) *value = [object longLongValue];
    return YES;
  }
  if (type && strchr("CSILQ", type)) {
    unsigned long long candidate = [object unsignedLongLongValue];
    if (candidate > INT64_MAX) return NO;
    if (value) *value = (int64_t)candidate;
    return YES;
  }
  return NO;
}

static void QONRemoteConfigV2IdentityAppendFramed(NSMutableData *data, NSData *value) {
  uint32_t length = CFSwapInt32HostToBig((uint32_t)value.length);
  [data appendBytes:&length length:sizeof(length)];
  [data appendData:value];
}

static NSString *QONRemoteConfigV2IdentitySHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return [hex copy];
}

@interface QONRemoteConfigV2ProjectIdentityStore ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
/** Framed into every key: which gateway and which token this record was learned from. */
@property (nonatomic, copy) NSString *deploymentTag;
@end

@implementation QONRemoteConfigV2ProjectIdentityStore

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
                              baseURL:(NSURL *)baseURL
                         projectToken:(NSString *)projectToken {
  if (!localStorage || baseURL.absoluteString.length == 0 || projectToken.length == 0) return nil;
  self = [super init];
  if (self) {
    _localStorage = localStorage;
    // Reduced to a digest once, so the token is never held alongside the record
    // it keys and never framed again at call time.
    NSMutableData *deployment = [NSMutableData new];
    QONRemoteConfigV2IdentityAppendFramed(deployment,
        [baseURL.absoluteString dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
    QONRemoteConfigV2IdentityAppendFramed(deployment,
        [projectToken dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
    _deploymentTag = QONRemoteConfigV2IdentitySHA256(deployment);
  }
  return self;
}

/** Identity-free by construction: the canonical user id never enters the framing. */
- (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2IdentityAppendFramed(framing,
      [@"remote-config-v2-project-identity-v2" dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2IdentityAppendFramed(framing,
      [self.deploymentTag dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2IdentityAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2IdentityAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  return [QONRemoteConfigV2ProjectIdentityPrefix
      stringByAppendingString:QONRemoteConfigV2IdentitySHA256(framing)];
}

/**
 An unreadable or foreign-shaped record reads as "nothing known".

 The record lives in the app's own storage, so the only realistic way to reach
 that state is a schema change or a truncated write, and refusing to fetch
 forever afterwards would be worse than re-learning from the next bootstrap.
 What it must never do is read as some *other* id.
 */
- (int64_t)projectIDForStorageKeyLocked:(NSString *)key {
  id object = nil;
  @try {
    object = [self.localStorage loadObjectForKey:key];
  } @catch (__unused NSException *exception) {
    return 0;
  }
  if (![object isKindOfClass:NSDictionary.class]) return 0;

  NSDictionary *dictionary = object;
  int64_t schema = 0;
  int64_t projectID = 0;
  if (!QONRemoteConfigV2IdentityExactInt64(dictionary[@"schema_version"], &schema) ||
      schema != QONRemoteConfigV2ProjectIdentitySchema ||
      !QONRemoteConfigV2IdentityExactInt64(dictionary[@"project_id"], &projectID) ||
      projectID <= 0 || projectID > QONRemoteConfigV2MaximumSafeInteger ||
      ![dictionary[@"scope_key"] isKindOfClass:NSString.class] ||
      ![dictionary[@"scope_key"] isEqualToString:key]) {
    return 0;
  }
  return projectID;
}

- (int64_t)projectIDForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return 0;
  @synchronized (self) {
    return [self projectIDForStorageKeyLocked:[self storageKeyForScope:scope]];
  }
}

- (QONRemoteConfigV2ProjectIdentityOutcome)establishProjectID:(int64_t)projectID
                                                     forScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope || projectID <= 0 || projectID > QONRemoteConfigV2MaximumSafeInteger) {
    return QONRemoteConfigV2ProjectIdentityOutcomeUnusable;
  }
  NSString *key = [self storageKeyForScope:scope];
  @synchronized (self) {
    int64_t known = [self projectIDForStorageKeyLocked:key];
    if (known == projectID) return QONRemoteConfigV2ProjectIdentityOutcomeConfirmed;
    if (known != 0) return QONRemoteConfigV2ProjectIdentityOutcomeConflict;

    NSDictionary *payload = @{
      @"schema_version": @(QONRemoteConfigV2ProjectIdentitySchema),
      @"scope_key": key,
      @"project_id": @(projectID),
    };
    @try {
      [self.localStorage storeObject:payload forKey:key];
      // Read back: a write that did not land would be re-learned on every launch,
      // and the conflict check would never fire.
      id readBack = [self.localStorage loadObjectForKey:key];
      if (![readBack isEqual:payload]) {
        return QONRemoteConfigV2ProjectIdentityOutcomePersistenceFailed;
      }
    } @catch (__unused NSException *exception) {
      return QONRemoteConfigV2ProjectIdentityOutcomePersistenceFailed;
    }
    return QONRemoteConfigV2ProjectIdentityOutcomeEstablished;
  }
}

@end
