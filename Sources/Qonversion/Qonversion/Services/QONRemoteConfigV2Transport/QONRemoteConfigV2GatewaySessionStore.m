#import "QONRemoteConfigV2GatewaySessionStore.h"
#import "QNLocalStorage.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NSUInteger const QONRemoteConfigV2GatewaySessionMaximumTokenBytes = 4096;

static NSInteger const QONRemoteConfigV2GatewaySessionSchema = 1;
static NSString *const QONRemoteConfigV2GatewaySessionPrefix =
    @"com.qonversion.keys.remote-config-v2-session.";

static BOOL QONRemoteConfigV2SessionExactInt64(id object, int64_t *value) {
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

static void QONRemoteConfigV2SessionAppendFramed(NSMutableData *data, NSData *value) {
  uint32_t length = CFSwapInt32HostToBig((uint32_t)value.length);
  [data appendBytes:&length length:sizeof(length)];
  [data appendData:value];
}

static NSString *QONRemoteConfigV2SessionSHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return [hex copy];
}

BOOL QONRemoteConfigV2GatewayValidHeaderValue(NSString *value, NSUInteger maximumBytes) {
  if (![value isKindOfClass:NSString.class] || value.length == 0) return NO;
  NSData *bytes = [value dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
  if (!bytes || bytes.length == 0 || bytes.length > maximumBytes) return NO;
  const unsigned char *raw = bytes.bytes;
  for (NSUInteger index = 0; index < bytes.length; index++) {
    // Visible ASCII only: CFNetwork silently drops a header carrying anything else.
    if (raw[index] < 0x21 || raw[index] > 0x7E) return NO;
  }
  return YES;
}

@implementation QONRemoteConfigV2GatewaySession

- (instancetype)initWithSessionToken:(NSString *)sessionToken
                           projectID:(int64_t)projectID
                         environment:(NSString *)environment
                    expiresAtSeconds:(int64_t)expiresAtSeconds {
  if (!QONRemoteConfigV2GatewayValidHeaderValue(
          sessionToken, QONRemoteConfigV2GatewaySessionMaximumTokenBytes) ||
      ![environment isKindOfClass:NSString.class] || environment.length == 0 ||
      [environment lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >
          QONRemoteConfigV2MaximumScopeComponentBytes ||
      projectID <= 0 || expiresAtSeconds < 0) {
    return nil;
  }
  self = [super init];
  if (self) {
    _sessionToken = [sessionToken copy];
    _projectID = projectID;
    _environment = [environment copy];
    _expiresAtSeconds = expiresAtSeconds;
  }
  return self;
}

- (id)copyWithZone:(__unused NSZone *)zone {
  return self;
}

- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2GatewaySession.class]) return NO;
  QONRemoteConfigV2GatewaySession *other = object;
  return [self.sessionToken isEqualToString:other.sessionToken] &&
      self.projectID == other.projectID &&
      [self.environment isEqualToString:other.environment] &&
      self.expiresAtSeconds == other.expiresAtSeconds;
}

- (NSUInteger)hash {
  return self.sessionToken.hash ^ (NSUInteger)self.projectID;
}

/** Deliberately opaque: the token must never reach a log or a crash report. */
- (NSString *)description {
  return [NSString stringWithFormat:@"<%@: project=%lld environment=%@ expires_at=%lld>",
                                    NSStringFromClass(self.class), self.projectID,
                                    self.environment, self.expiresAtSeconds];
}

- (NSString *)debugDescription {
  return self.description;
}

@end

@interface QONRemoteConfigV2GatewaySessionStore ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@end

@implementation QONRemoteConfigV2GatewaySessionStore

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  if (!localStorage) return nil;
  self = [super init];
  if (self) _localStorage = localStorage;
  return self;
}

+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2SessionAppendFramed(framing,
      [@"remote-config-v2-session-v1" dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2SessionAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2SessionAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2SessionAppendFramed(framing,
      [scope.canonicalUserID dataUsingEncoding:NSUTF8StringEncoding]);
  return [QONRemoteConfigV2GatewaySessionPrefix
      stringByAppendingString:QONRemoteConfigV2SessionSHA256(framing)];
}

- (nullable QONRemoteConfigV2GatewaySession *)sessionForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return nil;
  @synchronized (self) {
    id object = nil;
    @try {
      object = [self.localStorage
          loadObjectForKey:[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:scope]];
    } @catch (__unused NSException *exception) {
      return nil;
    }
    if (![object isKindOfClass:NSDictionary.class]) return nil;

    NSDictionary *dictionary = object;
    int64_t schema = 0;
    int64_t projectID = 0;
    int64_t expiresAt = 0;
    if (!QONRemoteConfigV2SessionExactInt64(dictionary[@"schema_version"], &schema) ||
        schema != QONRemoteConfigV2GatewaySessionSchema ||
        !QONRemoteConfigV2SessionExactInt64(dictionary[@"project_id"], &projectID) ||
        !QONRemoteConfigV2SessionExactInt64(dictionary[@"expires_at"], &expiresAt) ||
        ![dictionary[@"session_token"] isKindOfClass:NSString.class] ||
        ![dictionary[@"environment"] isKindOfClass:NSString.class] ||
        ![dictionary[@"scope_key"] isKindOfClass:NSString.class] ||
        ![dictionary[@"scope_key"] isEqualToString:
             [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:scope]]) {
      return nil;
    }
    return [[QONRemoteConfigV2GatewaySession alloc]
        initWithSessionToken:dictionary[@"session_token"]
                   projectID:projectID
                 environment:dictionary[@"environment"]
            expiresAtSeconds:expiresAt];
  }
}

- (BOOL)storeSession:(QONRemoteConfigV2GatewaySession *)session
            forScope:(QONRemoteConfigV2Scope *)scope {
  if (!session || !scope) return NO;
  NSString *key = [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:scope];
  NSDictionary *payload = @{
    @"schema_version": @(QONRemoteConfigV2GatewaySessionSchema),
    @"scope_key": key,
    @"session_token": session.sessionToken,
    @"project_id": @(session.projectID),
    @"environment": session.environment,
    @"expires_at": @(session.expiresAtSeconds),
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

- (void)removeSessionForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return;
  @synchronized (self) {
    @try {
      [self.localStorage
          removeObjectForKey:[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:scope]];
    } @catch (__unused NSException *exception) {}
  }
}

@end
