#import "QONRemoteConfigV2GatewayTransport.h"
#import "QONRemoteConfigJSON.h"
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NSString *const QONRemoteConfigV2GatewaySessionPath = @"v3/remote-config-v2/session";
NSString *const QONRemoteConfigV2GatewaySnapshotPath = @"v3/remote-config-v2/snapshot";
NSString *const QONRemoteConfigV2GatewaySessionHeader = @"X-Qonversion-RC-Session";
NSUInteger const QONRemoteConfigV2GatewayMaximumBootstrapBytes = 8192;

static NSUInteger const QONRemoteConfigV2GatewayMaximumContextComponentBytes = 256;
static int64_t const QONRemoteConfigV2GatewayMaximumRetryAfterMilliseconds = 86400000;

#pragma mark - Shared helpers

static BOOL QONRemoteConfigV2GatewayExactInt64(id object, int64_t *value) {
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

static BOOL QONRemoteConfigV2GatewayValidComponent(NSString *value) {
  return [value isKindOfClass:NSString.class] && value.length > 0 &&
      [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <=
          QONRemoteConfigV2GatewayMaximumContextComponentBytes;
}

/** Shape-only check. The strict parser still verifies the digest against the body. */
static BOOL QONRemoteConfigV2GatewayStrongETagShape(NSString *eTag) {
  return [eTag isKindOfClass:NSString.class] && eTag.length >= 3 &&
      [eTag hasPrefix:@"\""] && [eTag hasSuffix:@"\""];
}

static NSData *_Nullable QONRemoteConfigV2GatewayJSONBody(NSDictionary *object) {
  if (!object) return nil;
  if (![NSJSONSerialization isValidJSONObject:object]) return nil;
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                 options:NSJSONWritingSortedKeys
                                                   error:&error];
  if (!data || error) return nil;
  return data;
}

static BOOL QONRemoteConfigV2GatewayScopesEqual(QONRemoteConfigV2Scope *left,
                                                QONRemoteConfigV2Scope *right) {
  if (left == right) return YES;
  if (!left || !right) return NO;
  return [left.projectKey isEqualToString:right.projectKey] &&
      [left.environment isEqualToString:right.environment] &&
      [left.canonicalUserID isEqualToString:right.canonicalUserID];
}

#pragma mark - Client context

@implementation QONRemoteConfigV2ClientContext

- (instancetype)initWithPlatform:(NSString *)platform
                      appVersion:(NSString *)appVersion
                       osVersion:(NSString *)osVersion
                      sdkVersion:(NSString *)sdkVersion
                          locale:(NSString *)locale
                     deviceModel:(NSString *)deviceModel
        deviceInstalledAtSeconds:(NSNumber *)deviceInstalledAtSeconds {
  if (!QONRemoteConfigV2GatewayValidComponent(platform) ||
      !QONRemoteConfigV2GatewayValidComponent(appVersion) ||
      !QONRemoteConfigV2GatewayValidComponent(osVersion) ||
      !QONRemoteConfigV2GatewayValidComponent(sdkVersion) ||
      !QONRemoteConfigV2GatewayValidComponent(locale) ||
      !QONRemoteConfigV2GatewayValidComponent(deviceModel)) {
    return nil;
  }
  int64_t installedAt = 0;
  if (deviceInstalledAtSeconds &&
      (!QONRemoteConfigV2GatewayExactInt64(deviceInstalledAtSeconds, &installedAt) ||
       installedAt <= 0)) {
    return nil;
  }
  self = [super init];
  if (self) {
    _platform = [platform copy];
    _appVersion = [appVersion copy];
    _osVersion = [osVersion copy];
    _sdkVersion = [sdkVersion copy];
    _locale = [locale copy];
    _deviceModel = [deviceModel copy];
    _deviceInstalledAtSeconds = deviceInstalledAtSeconds ? @(installedAt) : nil;
  }
  return self;
}

- (id)copyWithZone:(__unused NSZone *)zone {
  return self;
}

- (nullable NSDictionary<NSString *, id> *)JSONObject {
  NSMutableDictionary *object = [NSMutableDictionary new];
  object[@"platform"] = self.platform;
  object[@"app_version"] = self.appVersion;
  object[@"os_version"] = self.osVersion;
  object[@"sdk_version"] = self.sdkVersion;
  object[@"locale"] = self.locale;
  object[@"device_model"] = self.deviceModel;
  if (self.deviceInstalledAtSeconds) {
    object[@"device_installed_at"] = self.deviceInstalledAtSeconds;
  }
  return [object copy];
}

@end

@interface QONRemoteConfigV2DeviceClientContextProvider ()
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, copy) NSString *appVersion;
@property (nonatomic, copy) NSString *osVersion;
@property (nonatomic, copy) NSString *sdkVersion;
@property (nonatomic, copy) NSString *locale;
@property (nonatomic, copy) NSString *deviceModel;
@property (nonatomic, strong) id<QONRemoteConfigV2DeviceInstallDateProviding> installDateProvider;
@end

@implementation QONRemoteConfigV2DeviceClientContextProvider

- (instancetype)initWithPlatform:(NSString *)platform
                      appVersion:(NSString *)appVersion
                       osVersion:(NSString *)osVersion
                      sdkVersion:(NSString *)sdkVersion
                          locale:(NSString *)locale
                     deviceModel:(NSString *)deviceModel
             installDateProvider:(id<QONRemoteConfigV2DeviceInstallDateProviding>)installDateProvider {
  if (!installDateProvider) return nil;
  self = [super init];
  if (self) {
    _platform = [platform copy];
    _appVersion = [appVersion copy];
    _osVersion = [osVersion copy];
    _sdkVersion = [sdkVersion copy];
    _locale = [locale copy];
    _deviceModel = [deviceModel copy];
    _installDateProvider = installDateProvider;
  }
  return self;
}

- (nullable QONRemoteConfigV2ClientContext *)currentClientContext {
  NSNumber *installedAt = nil;
  @try {
    installedAt = [self.installDateProvider deviceInstalledAtSeconds];
  } @catch (__unused NSException *exception) {
    installedAt = nil;
  }
  return [[QONRemoteConfigV2ClientContext alloc] initWithPlatform:self.platform
                                                       appVersion:self.appVersion
                                                        osVersion:self.osVersion
                                                       sdkVersion:self.sdkVersion
                                                           locale:self.locale
                                                      deviceModel:self.deviceModel
                                         deviceInstalledAtSeconds:installedAt];
}

@end

#pragma mark - HTTP executor

@interface QONRemoteConfigV2URLSessionHTTPExecutor ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation QONRemoteConfigV2URLSessionHTTPExecutor

- (instancetype)initWithSession:(NSURLSession *)session {
  if (!session) return nil;
  self = [super init];
  if (self) _session = session;
  return self;
}

- (void)executeRequest:(NSURLRequest *)request
            completion:(QONRemoteConfigV2HTTPCompletion)completion {
  NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    NSHTTPURLResponse *httpResponse =
        [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    completion(data, httpResponse, error);
  }];
  [task resume];
}

@end

#pragma mark - Transport

@interface QONRemoteConfigV2GatewayTransport ()
@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, copy) NSString *projectToken;
@property (nonatomic, strong) id<QONRemoteConfigV2HTTPExecuting> httpExecutor;
@property (nonatomic, strong) id<QONRemoteConfigV2GatewaySessionStoring> sessionStore;
@property (nonatomic, strong) id<QONRemoteConfigV2ClientContextProviding> clientContextProvider;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchClock> clock;
@property (nonatomic, copy, nullable) QONRemoteConfigV2TransportFailureObserver failureObserver;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *scope;
@property (nonatomic, assign) int64_t generation;
@end

@implementation QONRemoteConfigV2GatewayTransport

- (instancetype)initWithBaseURL:(NSURL *)baseURL
                   projectToken:(NSString *)projectToken
                   httpExecutor:(id<QONRemoteConfigV2HTTPExecuting>)httpExecutor
                   sessionStore:(id<QONRemoteConfigV2GatewaySessionStoring>)sessionStore
          clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider
                          clock:(id<QONRemoteConfigV2FetchClock>)clock
                failureObserver:(QONRemoteConfigV2TransportFailureObserver)failureObserver {
  if (!baseURL.scheme.length || !baseURL.host.length || ![projectToken isKindOfClass:NSString.class] ||
      projectToken.length == 0 || !httpExecutor || !sessionStore || !clientContextProvider || !clock) {
    return nil;
  }
  self = [super init];
  if (self) {
    _baseURL = baseURL;
    _projectToken = [projectToken copy];
    _httpExecutor = httpExecutor;
    _sessionStore = sessionStore;
    _clientContextProvider = clientContextProvider;
    _clock = clock;
    _failureObserver = [failureObserver copy];
  }
  return self;
}

- (void)updateScope:(QONRemoteConfigV2Scope *)scope {
  @synchronized (self) {
    self.scope = scope;
    self.generation += 1;
  }
}

#pragma mark - Fetch entry point

- (void)fetchRequest:(QONRemoteConfigV2FetchRequest *)request
          completion:(QONRemoteConfigV2FetchTransportCompletion)completion {
  if (!completion) return;

  __block BOOL responded = NO;
  QONRemoteConfigV2FetchTransportCompletion respond = ^(QONRemoteConfigV2FetchResponse *response) {
    BOOL shouldRespond = NO;
    @synchronized (self) {
      if (!responded) {
        responded = YES;
        shouldRespond = YES;
      }
    }
    if (shouldRespond) completion(response);
  };

  QONRemoteConfigV2Scope *scope = nil;
  int64_t generation = 0;
  @synchronized (self) {
    scope = self.scope;
    generation = self.generation;
  }
  if (!scope) {
    [self failRespond:respond
                 kind:QONRemoteConfigV2TransportFailureKindNotConfigured
           statusCode:nil
               retryAfterMilliseconds:nil];
    return;
  }

  QONRemoteConfigV2ClientContext *context = nil;
  @try {
    context = [self.clientContextProvider currentClientContext];
  } @catch (__unused NSException *exception) {
    context = nil;
  }
  NSData *snapshotBody = context ? QONRemoteConfigV2GatewayJSONBody(@{
    @"client_context": context.JSONObject ?: @{},
  }) : nil;
  if (!context || !snapshotBody) {
    [self failRespond:respond
                 kind:QONRemoteConfigV2TransportFailureKindNotConfigured
           statusCode:nil
               retryAfterMilliseconds:nil];
    return;
  }

  QONRemoteConfigV2GatewaySession *session = [self validSessionForScope:scope];
  if (session) {
    [self performSnapshotForScope:scope
                       generation:generation
                          session:session
                             body:snapshotBody
                      ifNoneMatch:request.ifNoneMatch
              allowReBootstrap:YES
                          respond:respond];
    return;
  }

  [self bootstrapForScope:scope generation:generation respond:respond completion:
      ^(QONRemoteConfigV2GatewaySession *freshSession) {
    // A session created inside this fetch is already fresh: a 401 on it is a
    // real rejection, so it must never trigger another bootstrap round.
    [self performSnapshotForScope:scope
                       generation:generation
                          session:freshSession
                             body:snapshotBody
                      ifNoneMatch:request.ifNoneMatch
              allowReBootstrap:NO
                          respond:respond];
  }];
}

#pragma mark - Bootstrap

- (nullable QONRemoteConfigV2GatewaySession *)validSessionForScope:(QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2GatewaySession *session = nil;
  @try {
    session = [self.sessionStore sessionForScope:scope];
  } @catch (__unused NSException *exception) {
    return nil;
  }
  if (!session) return nil;
  if (session.expiresAtSeconds <= 0) return session;

  int64_t nowMilliseconds = 0;
  @try {
    nowMilliseconds = [self.clock nowMilliseconds];
  } @catch (__unused NSException *exception) {
    return session;
  }
  return session.expiresAtSeconds > nowMilliseconds / 1000 ? session : nil;
}

- (void)bootstrapForScope:(QONRemoteConfigV2Scope *)scope
               generation:(int64_t)generation
                  respond:(QONRemoteConfigV2FetchTransportCompletion)respond
               completion:(void (^)(QONRemoteConfigV2GatewaySession *session))completion {
  NSData *body = QONRemoteConfigV2GatewayJSONBody(@{@"user_uid": scope.canonicalUserID});
  NSURLRequest *request = body ? [self requestWithPath:QONRemoteConfigV2GatewaySessionPath
                                                 body:body
                                         sessionToken:nil
                                          ifNoneMatch:nil]
                               : nil;
  if (!request) {
    [self failRespond:respond
                 kind:QONRemoteConfigV2TransportFailureKindNotConfigured
           statusCode:nil
               retryAfterMilliseconds:nil];
    return;
  }

  [self execute:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
    if (![self isCurrentScope:scope generation:generation]) {
      [self failRespond:respond
                   kind:QONRemoteConfigV2TransportFailureKindSuperseded
             statusCode:nil
                 retryAfterMilliseconds:nil];
      return;
    }
    if (error || !response) {
      [self failRespond:respond
                   kind:QONRemoteConfigV2TransportFailureKindBootstrapTransport
             statusCode:nil
                 retryAfterMilliseconds:nil];
      return;
    }

    NSInteger status = response.statusCode;
    if (status != 200) {
      QONRemoteConfigV2TransportFailureKind kind =
          QONRemoteConfigV2TransportFailureKindBootstrapUnavailable;
      if (status == 401 || status == 403) {
        kind = QONRemoteConfigV2TransportFailureKindBootstrapUnauthorized;
      } else if (status == 404) {
        kind = QONRemoteConfigV2TransportFailureKindBootstrapNotFound;
      }
      [self failRespond:respond
                   kind:kind
             statusCode:@(status)
                 retryAfterMilliseconds:[self retryAfterMillisecondsFrom:response]];
      return;
    }

    QONRemoteConfigV2GatewaySession *session = [self sessionFromBootstrapBody:data];
    if (!session) {
      [self failRespond:respond
                   kind:QONRemoteConfigV2TransportFailureKindBootstrapMalformed
             statusCode:@(status)
                 retryAfterMilliseconds:nil];
      return;
    }

    BOOL stored = NO;
    @try {
      stored = [self.sessionStore storeSession:session forScope:scope];
    } @catch (__unused NSException *exception) {
      stored = NO;
    }
    if (!stored) {
      [self failRespond:respond
                   kind:QONRemoteConfigV2TransportFailureKindBootstrapPersistenceFailed
             statusCode:nil
                 retryAfterMilliseconds:nil];
      return;
    }
    completion(session);
  }];
}

- (nullable QONRemoteConfigV2GatewaySession *)sessionFromBootstrapBody:(NSData *)body {
  if (!body) return nil;
  id object = QONRemoteConfigPortableJSONObject(body, QONRemoteConfigV2GatewayMaximumBootstrapBytes);
  if (![object isKindOfClass:NSDictionary.class]) return nil;

  NSDictionary *dictionary = object;
  int64_t projectID = 0;
  if (![dictionary[@"session_token"] isKindOfClass:NSString.class] ||
      ![dictionary[@"environment"] isKindOfClass:NSString.class] ||
      !QONRemoteConfigV2GatewayExactInt64(dictionary[@"project_id"], &projectID)) {
    return nil;
  }
  return [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:dictionary[@"session_token"]
                 projectID:projectID
               environment:dictionary[@"environment"]
          expiresAtSeconds:[self expiresAtSecondsFrom:dictionary[@"expires_at"]]];
}

/** Accepts epoch seconds or an ISO 8601 instant; anything else means "no stated expiry". */
- (int64_t)expiresAtSecondsFrom:(id)value {
  int64_t seconds = 0;
  if (QONRemoteConfigV2GatewayExactInt64(value, &seconds)) {
    return seconds > 0 ? seconds : 0;
  }
  if (![value isKindOfClass:NSString.class]) return 0;

  static NSISO8601DateFormatter *formatter = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    formatter = [NSISO8601DateFormatter new];
  });
  NSDate *date = nil;
  @synchronized (formatter) {
    date = [formatter dateFromString:value];
  }
  if (!date) return 0;
  NSTimeInterval interval = date.timeIntervalSince1970;
  if (!isfinite(interval) || interval <= 0 || interval >= (NSTimeInterval)INT64_MAX) return 0;
  return (int64_t)interval;
}

#pragma mark - Snapshot

- (void)performSnapshotForScope:(QONRemoteConfigV2Scope *)scope
                     generation:(int64_t)generation
                        session:(QONRemoteConfigV2GatewaySession *)session
                           body:(NSData *)body
                    ifNoneMatch:(NSString *)ifNoneMatch
               allowReBootstrap:(BOOL)allowReBootstrap
                        respond:(QONRemoteConfigV2FetchTransportCompletion)respond {
  NSURLRequest *request = [self requestWithPath:QONRemoteConfigV2GatewaySnapshotPath
                                           body:body
                                   sessionToken:session.sessionToken
                                    ifNoneMatch:ifNoneMatch];
  if (!request) {
    [self failRespond:respond
                 kind:QONRemoteConfigV2TransportFailureKindNotConfigured
           statusCode:nil
               retryAfterMilliseconds:nil];
    return;
  }

  [self execute:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
    if (![self isCurrentScope:scope generation:generation]) {
      [self failRespond:respond
                   kind:QONRemoteConfigV2TransportFailureKindSuperseded
             statusCode:nil
                 retryAfterMilliseconds:nil];
      return;
    }
    if (error || !response) {
      [self failRespond:respond
                   kind:QONRemoteConfigV2TransportFailureKindSnapshotTransport
             statusCode:nil
                 retryAfterMilliseconds:nil];
      return;
    }

    NSInteger status = response.statusCode;
    NSString *eTag = [response valueForHTTPHeaderField:@"ETag"];

    if (status == 200) {
      if (data.length == 0 || !QONRemoteConfigV2GatewayStrongETagShape(eTag)) {
        [self failRespond:respond
                     kind:QONRemoteConfigV2TransportFailureKindSnapshotMalformed
               statusCode:@(status)
                   retryAfterMilliseconds:nil];
        return;
      }
      // Exact bytes as received: no decode, no re-serialization, no copy semantics change.
      respond([QONRemoteConfigV2FetchResponse successWithBody:data strongETag:eTag]);
      return;
    }

    if (status == 304) {
      NSString *validator = QONRemoteConfigV2GatewayStrongETagShape(eTag) ? eTag : ifNoneMatch;
      respond([QONRemoteConfigV2FetchResponse notModifiedWithStrongETag:validator]);
      return;
    }

    if (status == 401) {
      @try {
        [self.sessionStore removeSessionForScope:scope];
      } @catch (__unused NSException *exception) {}

      if (!allowReBootstrap) {
        [self failRespond:respond
                     kind:QONRemoteConfigV2TransportFailureKindSnapshotUnauthorized
               statusCode:@(status)
                   retryAfterMilliseconds:nil];
        return;
      }
      [self bootstrapForScope:scope generation:generation respond:respond completion:
          ^(QONRemoteConfigV2GatewaySession *freshSession) {
        [self performSnapshotForScope:scope
                           generation:generation
                              session:freshSession
                                 body:body
                          ifNoneMatch:ifNoneMatch
                  allowReBootstrap:NO
                              respond:respond];
      }];
      return;
    }

    QONRemoteConfigV2TransportFailureKind kind =
        QONRemoteConfigV2TransportFailureKindSnapshotUnavailable;
    if (status == 403) {
      kind = QONRemoteConfigV2TransportFailureKindSnapshotUnauthorized;
    } else if (status == 404) {
      kind = QONRemoteConfigV2TransportFailureKindSnapshotNotFound;
    }
    [self failRespond:respond
                 kind:kind
           statusCode:@(status)
               retryAfterMilliseconds:[self retryAfterMillisecondsFrom:response]];
  }];
}

#pragma mark - Plumbing

- (BOOL)isCurrentScope:(QONRemoteConfigV2Scope *)scope generation:(int64_t)generation {
  @synchronized (self) {
    return self.generation == generation && QONRemoteConfigV2GatewayScopesEqual(self.scope, scope);
  }
}

- (nullable NSURLRequest *)requestWithPath:(NSString *)path
                                      body:(NSData *)body
                              sessionToken:(nullable NSString *)sessionToken
                               ifNoneMatch:(nullable NSString *)ifNoneMatch {
  NSString *base = self.baseURL.absoluteString;
  if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
  NSURL *url = [NSURL URLWithString:[base stringByAppendingString:path]];
  if (!url || !body) return nil;

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = body;
  [request setValue:[@"Bearer " stringByAppendingString:self.projectToken]
      forHTTPHeaderField:@"Authorization"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  if (sessionToken.length > 0) {
    [request setValue:sessionToken forHTTPHeaderField:QONRemoteConfigV2GatewaySessionHeader];
  }
  if (ifNoneMatch.length > 0) {
    // Passed through byte for byte: a rewritten validator would defeat 304 recovery.
    [request setValue:ifNoneMatch forHTTPHeaderField:@"If-None-Match"];
  }
  return request;
}

- (void)execute:(NSURLRequest *)request completion:(QONRemoteConfigV2HTTPCompletion)completion {
  __block BOOL delivered = NO;
  QONRemoteConfigV2HTTPCompletion once =
      ^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
    BOOL shouldDeliver = NO;
    @synchronized (self) {
      if (!delivered) {
        delivered = YES;
        shouldDeliver = YES;
      }
    }
    if (shouldDeliver) completion(data, response, error);
  };

  @try {
    [self.httpExecutor executeRequest:request completion:once];
  } @catch (__unused NSException *exception) {
    once(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil]);
  }
}

- (nullable NSNumber *)retryAfterMillisecondsFrom:(NSHTTPURLResponse *)response {
  NSString *value = [response valueForHTTPHeaderField:@"Retry-After"];
  if (value.length == 0) return nil;
  NSScanner *scanner = [NSScanner scannerWithString:value];
  long long seconds = 0;
  if (![scanner scanLongLong:&seconds] || !scanner.isAtEnd || seconds < 0) return nil;
  if (seconds > QONRemoteConfigV2GatewayMaximumRetryAfterMilliseconds / 1000) {
    return @(QONRemoteConfigV2GatewayMaximumRetryAfterMilliseconds);
  }
  return @(seconds * 1000);
}

- (void)failRespond:(QONRemoteConfigV2FetchTransportCompletion)respond
               kind:(QONRemoteConfigV2TransportFailureKind)kind
         statusCode:(nullable NSNumber *)statusCode
     retryAfterMilliseconds:(nullable NSNumber *)retryAfterMilliseconds {
  QONRemoteConfigV2TransportFailureObserver observer = self.failureObserver;
  if (observer) {
    @try {
      observer(kind, statusCode);
    } @catch (__unused NSException *exception) {}
  }
  respond([QONRemoteConfigV2FetchResponse failureWithStatusCode:statusCode
                                         retryAfterMilliseconds:retryAfterMilliseconds]);
}

@end
