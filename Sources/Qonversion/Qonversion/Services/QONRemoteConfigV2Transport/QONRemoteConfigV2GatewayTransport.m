#import "QONRemoteConfigV2GatewayTransport.h"
#import "QONRemoteConfigJSON.h"
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NSString *const QONRemoteConfigV2GatewaySessionPath = @"v3/remote-config-v2/session";
NSString *const QONRemoteConfigV2GatewaySnapshotPath = @"v3/remote-config-v2/snapshot";
NSString *const QONRemoteConfigV2GatewayAckPath = @"v3/remote-config-v2/ack";
NSString *const QONRemoteConfigV2GatewayTelemetryPath = @"v3/remote-config-v2/telemetry";
NSString *const QONRemoteConfigV2GatewaySessionHeader = @"X-Qonversion-RC-Session";
NSUInteger const QONRemoteConfigV2GatewayMaximumBootstrapBytes = 8192;

static NSUInteger const QONRemoteConfigV2GatewayMaximumContextComponentBytes = 256;
static int64_t const QONRemoteConfigV2GatewayMaximumRetryAfterMilliseconds = 86400000;

/**
 How a bootstrap reports that it could not mint a session.

 The bootstrap is shared by two routes that speak different vocabularies, so it
 states the refusal in its own terms — a typed failure kind plus whatever the
 gateway answered — and lets each caller translate. The fetch path turns it into
 a QONRemoteConfigV2FetchResponse; the ack path turns it into a
 QONRemoteConfigV2AckResponse. Neither re-derives the other's meaning.
 */
typedef void (^QONRemoteConfigV2GatewayRefusal)(QONRemoteConfigV2TransportFailureKind kind,
                                                NSNumber *_Nullable statusCode,
                                                NSNumber *_Nullable retryAfterMilliseconds);

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


// -[NSHTTPURLResponse valueForHTTPHeaderField:] is iOS 13/tvOS 13+; the SDK
// supports older deployment targets, so header lookup goes through
// allHeaderFields with the case-insensitive comparison HTTP requires.
static NSString *_Nullable QONRemoteConfigV2HeaderValue(NSHTTPURLResponse *response, NSString *field) {
  for (id key in response.allHeaderFields) {
    if ([key isKindOfClass:[NSString class]] &&
        [(NSString *)key caseInsensitiveCompare:field] == NSOrderedSame) {
      id value = response.allHeaderFields[key];
      return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
    }
  }
  return nil;
}

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

/** Stands in for a device fact the platform would not tell us. */
static NSString *const kQONRemoteConfigV2UnknownComponent = @"UNKNOWN";

static NSString *QONRemoteConfigV2NormalizedComponent(NSString *_Nullable value) {
  return value.length > 0 ? value : kQONRemoteConfigV2UnknownComponent;
}

/**
 An Apple locale identifier, reshaped into the tag Android states.

 `NSLocale` hands out identifiers like `en_US@rg=gbzzzz` or, from a language tag
 source, `en-US`. Android sends `toLanguageTag()` with its dashes turned into
 underscores, and `und` for a locale it could not determine. Everything after
 the first `@` is a keyword list — calendar, region override, numbering system —
 which is a preference rather than a locale and would fragment every targeting
 rule that matched on it.
 */
static NSString *QONRemoteConfigV2NormalizedLocale(NSString *_Nullable identifier) {
  NSString *value = identifier ?: @"";
  NSRange keywords = [value rangeOfString:@"@"];
  if (keywords.location != NSNotFound) {
    value = [value substringToIndex:keywords.location];
  }
  value = [value stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
  if (value.length == 0 || [value isEqualToString:@"und"]) {
    return kQONRemoteConfigV2UnknownComponent;
  }
  return value;
}

@implementation QONRemoteConfigV2DeviceClientContextProvider

+ (instancetype)providerWithPlatform:(NSString *)platform
                          appVersion:(NSString *)appVersion
                           osVersion:(NSString *)osVersion
                          sdkVersion:(NSString *)sdkVersion
                    localeIdentifier:(NSString *)localeIdentifier
                         deviceModel:(NSString *)deviceModel
                 installDateProvider:(id<QONRemoteConfigV2DeviceInstallDateProviding>)installDateProvider {
  // `lowercaseString` is the locale-independent one on purpose: the Turkish
  // dotless i would otherwise turn `iOS` into something no rule matches.
  NSString *normalizedPlatform = platform.length > 0
      ? platform.lowercaseString
      : kQONRemoteConfigV2UnknownComponent;

  return [[self alloc] initWithPlatform:normalizedPlatform
                             appVersion:QONRemoteConfigV2NormalizedComponent(appVersion)
                              osVersion:QONRemoteConfigV2NormalizedComponent(osVersion)
                             sdkVersion:QONRemoteConfigV2NormalizedComponent(sdkVersion)
                                 locale:QONRemoteConfigV2NormalizedLocale(localeIdentifier)
                            deviceModel:QONRemoteConfigV2NormalizedComponent(deviceModel)
                    installDateProvider:installDateProvider];
}

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
@property (nonatomic, strong) id<QONRemoteConfigV2ProjectIdentityStoring> projectIdentityStore;
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
            projectIdentityStore:(id<QONRemoteConfigV2ProjectIdentityStoring>)projectIdentityStore
          clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider
                          clock:(id<QONRemoteConfigV2FetchClock>)clock
                failureObserver:(QONRemoteConfigV2TransportFailureObserver)failureObserver {
  if (!baseURL.scheme.length || !baseURL.host.length || !httpExecutor || !sessionStore ||
      !projectIdentityStore || !clientContextProvider || !clock ||
      !QONRemoteConfigV2GatewayValidHeaderValue(
          projectToken, QONRemoteConfigV2GatewaySessionMaximumTokenBytes)) {
    return nil;
  }
  self = [super init];
  if (self) {
    _baseURL = baseURL;
    _projectToken = [projectToken copy];
    _httpExecutor = httpExecutor;
    _sessionStore = sessionStore;
    _projectIdentityStore = projectIdentityStore;
    _clientContextProvider = clientContextProvider;
    _clock = clock;
    _failureObserver = [failureObserver copy];
  }
  return self;
}

- (void)updateScope:(QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2Scope *retired = nil;
  @synchronized (self) {
    if (QONRemoteConfigV2GatewayScopesEqual(self.scope, scope)) return;
    retired = self.scope;
    self.scope = scope;
    self.generation += 1;
  }
  // The retired identity's bearer token is unusable from here on; dropping it
  // keeps it from lingering at rest for the lifetime of the installation.
  if (retired) {
    @try {
      [self.sessionStore removeSessionForScope:retired];
    } @catch (__unused NSException *exception) {}
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

  [self bootstrapForScope:scope
               generation:generation
                   refuse:[self fetchRefusalForRespond:respond]
               completion:^(QONRemoteConfigV2GatewaySession *freshSession) {
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

#pragma mark - Activation ack

/**
 Reports one activation out of band — POST {baseURL}/v3/remote-config-v2/ack.

 The `scope` the ack was queued for is compared against the identity the
 transport currently addresses: an identity change between queueing and sending
 must never let one identity's session vouch for another identity's activation,
 so the attempt is refused as `NotAddressable` (which costs the sender no retry
 budget) rather than sent.

 Failure classification is deliberately coarse, because the gateway answers
 opaquely: `2xx` is delivered, `429`/`5xx`/transport faults are retryable, and
 everything else — including a `401` that survives one re-bootstrap and the
 `404` of a gateway that does not serve this route yet — is permanent.
 */
- (void)sendAck:(QONRemoteConfigV2ActivationAck *)ack
       forScope:(QONRemoteConfigV2Scope *)scope
     completion:(QONRemoteConfigV2AckCompletion)completion {
  if (!completion) return;

  __block BOOL responded = NO;
  QONRemoteConfigV2AckCompletion respond = ^(QONRemoteConfigV2AckResponse response) {
    BOOL shouldRespond = NO;
    @synchronized (self) {
      if (!responded) {
        responded = YES;
        shouldRespond = YES;
      }
    }
    if (shouldRespond) completion(response);
  };

  QONRemoteConfigV2Scope *current = nil;
  int64_t generation = 0;
  @synchronized (self) {
    current = self.scope;
    generation = self.generation;
  }
  if (!ack || !scope || !QONRemoteConfigV2GatewayScopesEqual(current, scope)) {
    respond(QONRemoteConfigV2AckResponseNotAddressable);
    return;
  }

  NSData *body = QONRemoteConfigV2GatewayJSONBody(@{
    @"release_number": @(ack.releaseNumber),
    @"activated_at": @(ack.activatedAtSeconds),
  });
  if (!body) {
    // An ack this process cannot even encode will not encode any better later.
    respond(QONRemoteConfigV2AckResponsePermanent);
    return;
  }

  QONRemoteConfigV2GatewaySession *session = [self validSessionForScope:scope];
  if (session) {
    [self performAckForScope:scope
                  generation:generation
                     session:session
                        body:body
            allowReBootstrap:YES
                     respond:respond];
    return;
  }
  [self bootstrapForScope:scope
               generation:generation
                   refuse:[self ackRefusalForRespond:respond]
               completion:^(QONRemoteConfigV2GatewaySession *freshSession) {
    // A session minted inside this ack is already fresh: a 401 on it is a real
    // rejection, so it must never trigger another bootstrap round.
    [self performAckForScope:scope
                  generation:generation
                     session:freshSession
                        body:body
            allowReBootstrap:NO
                     respond:respond];
  }];
}

- (void)performAckForScope:(QONRemoteConfigV2Scope *)scope
                generation:(int64_t)generation
                   session:(QONRemoteConfigV2GatewaySession *)session
                      body:(NSData *)body
          allowReBootstrap:(BOOL)allowReBootstrap
                   respond:(QONRemoteConfigV2AckCompletion)respond {
  NSURLRequest *request = [self requestWithPath:QONRemoteConfigV2GatewayAckPath
                                           body:body
                                   sessionToken:session.sessionToken
                                    ifNoneMatch:nil];
  if (!request) {
    respond(QONRemoteConfigV2AckResponsePermanent);
    return;
  }

  [self execute:request completion:^(__unused NSData *data, NSHTTPURLResponse *response,
                                     NSError *error) {
    if (![self isCurrentScope:scope generation:generation]) {
      // Not an attempt: the identity moved on, and the ack is still owed by the
      // identity that queued it.
      respond(QONRemoteConfigV2AckResponseNotAddressable);
      return;
    }
    if (error || !response) {
      respond(QONRemoteConfigV2AckResponseRetryable);
      return;
    }

    NSInteger status = response.statusCode;
    if (status >= 200 && status <= 299) {
      respond(QONRemoteConfigV2AckResponseDelivered);
      return;
    }
    if (status == 401) {
      // Deliberately NOT removing the stored session: it is shared with the
      // config read path, and an out-of-band signal may not invalidate state
      // that path depends on. Minting simply replaces it if it really is dead,
      // and the read path applies its own 401 rule.
      if (!allowReBootstrap) {
        respond(QONRemoteConfigV2AckResponsePermanent);
        return;
      }
      [self bootstrapForScope:scope
                   generation:generation
                       refuse:[self ackRefusalForRespond:respond]
                   completion:^(QONRemoteConfigV2GatewaySession *freshSession) {
        [self performAckForScope:scope
                      generation:generation
                         session:freshSession
                            body:body
                allowReBootstrap:NO
                         respond:respond];
      }];
      return;
    }
    if (status == 429 || (status >= 500 && status <= 599)) {
      respond(QONRemoteConfigV2AckResponseRetryable);
      return;
    }
    respond(QONRemoteConfigV2AckResponsePermanent);
  }];
}

/** A bootstrap refusal, seen from the ack route. */
- (QONRemoteConfigV2GatewayRefusal)ackRefusalForRespond:(QONRemoteConfigV2AckCompletion)respond {
  return ^(QONRemoteConfigV2TransportFailureKind kind, NSNumber *statusCode,
           __unused NSNumber *retryAfterMilliseconds) {
    // The ack route never reports through the failure observer: that observer
    // belongs to the fetch policy, and an out-of-band signal may not feed it.
    switch (kind) {
      case QONRemoteConfigV2TransportFailureKindSuperseded:
        respond(QONRemoteConfigV2AckResponseNotAddressable);
        return;
      case QONRemoteConfigV2TransportFailureKindBootstrapTransport:
      // A 200 that carried no usable session is a gateway contract violation a
      // later attempt may well not repeat, and a storage fault is transient by
      // nature.
      case QONRemoteConfigV2TransportFailureKindBootstrapMalformed:
      case QONRemoteConfigV2TransportFailureKindBootstrapPersistenceFailed:
      case QONRemoteConfigV2TransportFailureKindProjectIdentityPersistenceFailed:
        respond(QONRemoteConfigV2AckResponseRetryable);
        return;
      case QONRemoteConfigV2TransportFailureKindBootstrapUnavailable: {
        NSInteger status = statusCode ? statusCode.integerValue : 0;
        respond(status == 429 || (status >= 500 && status <= 599)
                    ? QONRemoteConfigV2AckResponseRetryable
                    : QONRemoteConfigV2AckResponsePermanent);
        return;
      }
      default:
        // A refused credential, an absent route, a project the ledger refuses to
        // rebind, an unbuildable request: retrying only repeats the answer.
        respond(QONRemoteConfigV2AckResponsePermanent);
        return;
    }
  };
}

#pragma mark - Client telemetry

/** The ack vocabulary, seen from the telemetry route: the two are congruent. */
static QONRemoteConfigV2TelemetryResponse QONRemoteConfigV2TelemetryResponseFromAck(
    QONRemoteConfigV2AckResponse response) {
  switch (response) {
    case QONRemoteConfigV2AckResponseDelivered:
      return QONRemoteConfigV2TelemetryResponseDelivered;
    case QONRemoteConfigV2AckResponsePermanent:
      return QONRemoteConfigV2TelemetryResponsePermanent;
    case QONRemoteConfigV2AckResponseRetryable:
      return QONRemoteConfigV2TelemetryResponseRetryable;
    case QONRemoteConfigV2AckResponseNotAddressable:
      return QONRemoteConfigV2TelemetryResponseNotAddressable;
  }
  return QONRemoteConfigV2TelemetryResponseRetryable;
}

/**
 Ships one coalesced telemetry batch — POST {baseURL}/v3/remote-config-v2/telemetry.

 Same rules as the ack route, for the same reasons: the scope the batch was
 collected for is compared against the identity the transport currently
 addresses, a `401` is retried through exactly one re-bootstrap and never drops
 the stored session (the config read path depends on it), and the whole route is
 invisible to the failure observer, which belongs to the fetch policy.

 A batch this process cannot encode — an event the contract refuses, or more
 events than one request may carry — is refused as permanent rather than sent:
 the gateway would reject the whole request anyway, and it will encode no better
 later.
 */
- (void)sendTelemetryBatch:(NSArray<QONRemoteConfigV2TelemetryEvent *> *)events
                   forScope:(QONRemoteConfigV2Scope *)scope
                 completion:(QONRemoteConfigV2TelemetryCompletion)completion {
  if (!completion) return;

  __block BOOL responded = NO;
  QONRemoteConfigV2TelemetryCompletion respond = ^(QONRemoteConfigV2TelemetryResponse response) {
    BOOL shouldRespond = NO;
    @synchronized (self) {
      if (!responded) {
        responded = YES;
        shouldRespond = YES;
      }
    }
    if (shouldRespond) completion(response);
  };

  QONRemoteConfigV2Scope *current = nil;
  int64_t generation = 0;
  @synchronized (self) {
    current = self.scope;
    generation = self.generation;
  }
  if (!scope || !QONRemoteConfigV2GatewayScopesEqual(current, scope)) {
    respond(QONRemoteConfigV2TelemetryResponseNotAddressable);
    return;
  }

  NSData *body = [self telemetryBodyForEvents:events];
  if (!body) {
    respond(QONRemoteConfigV2TelemetryResponsePermanent);
    return;
  }

  QONRemoteConfigV2GatewaySession *session = [self validSessionForScope:scope];
  if (!session) {
    // Telemetry never establishes a session. It has a 30-second tick, so an
    // install that has not yet fetched would otherwise bootstrap the whole
    // fleet on a timer, and racing the config path's own bootstrap would mint
    // sessions nobody asked for. No request is made, no retry budget is spent,
    // and the events stay buffered for whenever the read path does the work.
    respond(QONRemoteConfigV2TelemetryResponseNotAddressable);
    return;
  }
  [self performTelemetryForScope:scope
                      generation:generation
                         session:session
                            body:body
                allowReBootstrap:YES
                         respond:respond];
}

- (nullable NSData *)telemetryBodyForEvents:(NSArray<QONRemoteConfigV2TelemetryEvent *> *)events {
  if (![events isKindOfClass:NSArray.class] || events.count == 0 ||
      events.count > QONRemoteConfigV2TelemetryMaximumBatchEntries) {
    return nil;
  }
  NSMutableArray<NSDictionary<NSString *, id> *> *objects =
      [NSMutableArray arrayWithCapacity:events.count];
  for (QONRemoteConfigV2TelemetryEvent *event in events) {
    if (![event isKindOfClass:QONRemoteConfigV2TelemetryEvent.class]) return nil;
    NSDictionary<NSString *, id> *object = [event JSONObject];
    if (!object) return nil;
    [objects addObject:object];
  }
  return QONRemoteConfigV2GatewayJSONBody(@{@"events": [objects copy]});
}

- (void)performTelemetryForScope:(QONRemoteConfigV2Scope *)scope
                      generation:(int64_t)generation
                         session:(QONRemoteConfigV2GatewaySession *)session
                            body:(NSData *)body
                allowReBootstrap:(BOOL)allowReBootstrap
                         respond:(QONRemoteConfigV2TelemetryCompletion)respond {
  NSURLRequest *request = [self requestWithPath:QONRemoteConfigV2GatewayTelemetryPath
                                           body:body
                                   sessionToken:session.sessionToken
                                    ifNoneMatch:nil];
  if (!request) {
    respond(QONRemoteConfigV2TelemetryResponsePermanent);
    return;
  }

  [self execute:request completion:^(__unused NSData *data, NSHTTPURLResponse *response,
                                     NSError *error) {
    if (![self isCurrentScope:scope generation:generation]) {
      // Not an attempt: the identity moved on, and the events are still owed by
      // the identity that produced them.
      respond(QONRemoteConfigV2TelemetryResponseNotAddressable);
      return;
    }
    if (error || !response) {
      respond(QONRemoteConfigV2TelemetryResponseRetryable);
      return;
    }

    NSInteger status = response.statusCode;
    if (status >= 200 && status <= 299) {
      respond(QONRemoteConfigV2TelemetryResponseDelivered);
      return;
    }
    if (status == 401) {
      // Deliberately NOT removing the stored session: it is shared with the
      // config read path, and an out-of-band signal may not invalidate state
      // that path depends on. This is the one bootstrap telemetry may cause,
      // and only because the session it already had was refused.
      if (!allowReBootstrap) {
        // Terminal rather than retryable, exactly as the ack route treats it: a
        // credential refused twice will be refused again, and telemetry is the
        // one signal allowed to give up on a batch.
        respond(QONRemoteConfigV2TelemetryResponsePermanent);
        return;
      }
      [self bootstrapForScope:scope
                   generation:generation
                       refuse:[self telemetryRefusalForRespond:respond]
                   completion:^(QONRemoteConfigV2GatewaySession *freshSession) {
        [self performTelemetryForScope:scope
                            generation:generation
                               session:freshSession
                                  body:body
                      allowReBootstrap:NO
                               respond:respond];
      }];
      return;
    }
    if (status == 429 || (status >= 500 && status <= 599)) {
      respond(QONRemoteConfigV2TelemetryResponseRetryable);
      return;
    }
    // A 400 lands here: the contract makes it terminal, and the sender drops the
    // batch rather than re-offering bytes the gateway has already refused.
    respond(QONRemoteConfigV2TelemetryResponsePermanent);
  }];
}

/** A bootstrap refusal, seen from the telemetry route. */
- (QONRemoteConfigV2GatewayRefusal)telemetryRefusalForRespond:
    (QONRemoteConfigV2TelemetryCompletion)respond {
  return [self ackRefusalForRespond:^(QONRemoteConfigV2AckResponse response) {
    respond(QONRemoteConfigV2TelemetryResponseFromAck(response));
  }];
}

#pragma mark - Project identity

/**
 Reconciles the `project_id` a freshly bootstrapped session states with what this
 installation already learned, and reports the outcome as a typed failure when it
 cannot be used. Returns YES when the caller may proceed with `session.projectID`.

 Only the bootstrap path calls this: a live bootstrap response is the one thing
 allowed to establish the id. A stored session is checked against the ledger
 instead, in validSessionForScope:, and dropped when it disagrees.
 */
- (BOOL)confirmProjectIdentityForSession:(QONRemoteConfigV2GatewaySession *)session
                                   scope:(QONRemoteConfigV2Scope *)scope
                                  refuse:(QONRemoteConfigV2GatewayRefusal)refuse {
  QONRemoteConfigV2ProjectIdentityOutcome outcome =
      QONRemoteConfigV2ProjectIdentityOutcomePersistenceFailed;
  @try {
    outcome = [self.projectIdentityStore establishProjectID:session.projectID forScope:scope];
  } @catch (__unused NSException *exception) {
    outcome = QONRemoteConfigV2ProjectIdentityOutcomePersistenceFailed;
  }
  switch (outcome) {
    case QONRemoteConfigV2ProjectIdentityOutcomeEstablished:
    case QONRemoteConfigV2ProjectIdentityOutcomeConfirmed:
      return YES;
    case QONRemoteConfigV2ProjectIdentityOutcomeConflict:
      // No status code: this is not something the gateway answered with, and
      // fabricating one would misreport it. It stays retryable and therefore
      // backs off, which is right — the disagreement is durable, so every
      // retry must keep failing instead of quietly rebinding the project.
      refuse(QONRemoteConfigV2TransportFailureKindProjectIdentityConflict, nil, nil);
      return NO;
    case QONRemoteConfigV2ProjectIdentityOutcomeUnusable:
      // The id itself is out of range, which makes the bootstrap that stated it
      // malformed rather than the storage faulty.
      refuse(QONRemoteConfigV2TransportFailureKindBootstrapMalformed, nil, nil);
      return NO;
    case QONRemoteConfigV2ProjectIdentityOutcomePersistenceFailed:
      refuse(QONRemoteConfigV2TransportFailureKindProjectIdentityPersistenceFailed, nil, nil);
      return NO;
  }
  refuse(QONRemoteConfigV2TransportFailureKindProjectIdentityPersistenceFailed, nil, nil);
  return NO;
}

/** The refusal a fetch answers with: exactly the previous failRespond: behaviour. */
- (QONRemoteConfigV2GatewayRefusal)fetchRefusalForRespond:
    (QONRemoteConfigV2FetchTransportCompletion)respond {
  return ^(QONRemoteConfigV2TransportFailureKind kind, NSNumber *statusCode,
           NSNumber *retryAfterMilliseconds) {
    [self failRespond:respond
                 kind:kind
           statusCode:statusCode
               retryAfterMilliseconds:retryAfterMilliseconds];
  };
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

  // A stored session is not a source of truth for the project id — only a live
  // bootstrap is. If the ledger does not already agree with it, the session is
  // dropped so the fetch bootstraps and learns (or conflicts) honestly.
  int64_t learned = 0;
  @try {
    learned = [self.projectIdentityStore projectIDForScope:scope];
  } @catch (__unused NSException *exception) {
    learned = 0;
  }
  if (learned != session.projectID) {
    @try {
      [self.sessionStore removeSessionForScope:scope];
    } @catch (__unused NSException *exception) {}
    return nil;
  }

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
                   refuse:(QONRemoteConfigV2GatewayRefusal)refuse
               completion:(void (^)(QONRemoteConfigV2GatewaySession *session))completion {
  NSData *body = QONRemoteConfigV2GatewayJSONBody(@{@"user_uid": scope.canonicalUserID});
  NSURLRequest *request = body ? [self requestWithPath:QONRemoteConfigV2GatewaySessionPath
                                                 body:body
                                         sessionToken:nil
                                          ifNoneMatch:nil]
                               : nil;
  if (!request) {
    refuse(QONRemoteConfigV2TransportFailureKindNotConfigured, nil, nil);
    return;
  }

  [self execute:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
    if (![self isCurrentScope:scope generation:generation]) {
      refuse(QONRemoteConfigV2TransportFailureKindSuperseded, nil, nil);
      return;
    }
    if (error || !response) {
      refuse(QONRemoteConfigV2TransportFailureKindBootstrapTransport, nil, nil);
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
      refuse(kind, @(status), [self retryAfterMillisecondsFrom:response]);
      return;
    }

    QONRemoteConfigV2GatewaySession *session = [self sessionFromBootstrapBody:data];
    // A session issued for another environment would be stored under this
    // scope's key and then rejected at admission on every fetch, with no
    // diagnosable signal. Refuse it here instead.
    if (session && ![session.environment isEqualToString:scope.environment]) session = nil;
    if (!session) {
      refuse(QONRemoteConfigV2TransportFailureKindBootstrapMalformed, @(status), nil);
      return;
    }

    // Before the token is stored, not after: a session belonging to another
    // project must not be left at rest under this scope's key.
    if (![self confirmProjectIdentityForSession:session scope:scope refuse:refuse]) return;

    BOOL stored = NO;
    @try {
      stored = [self.sessionStore storeSession:session forScope:scope];
    } @catch (__unused NSException *exception) {
      stored = NO;
    }
    if (!stored) {
      refuse(QONRemoteConfigV2TransportFailureKindBootstrapPersistenceFailed, nil, nil);
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
  // Reconciled already: a fresh session by the bootstrap that created it, a
  // reused one by validSessionForScope:. Neither reaches here unconfirmed.
  int64_t projectID = session.projectID;

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
    NSString *eTag = QONRemoteConfigV2HeaderValue(response, @"ETag");

    if (status == 200) {
      if (data.length == 0 || !QONRemoteConfigV2GatewayStrongETagShape(eTag)) {
        [self failRespond:respond
                     kind:QONRemoteConfigV2TransportFailureKindSnapshotMalformed
               statusCode:@(status)
                   retryAfterMilliseconds:nil];
        return;
      }
      // Exact bytes as received: no decode, no re-serialization, no copy semantics change.
      respond([QONRemoteConfigV2FetchResponse successWithBody:data
                                                   strongETag:eTag
                                                    projectID:projectID]);
      return;
    }

    if (status == 304) {
      // A 304 answering an unconditional request is a protocol violation: there
      // is no validator to recover from, so it must not look like a hit.
      if (ifNoneMatch.length == 0) {
        [self failRespond:respond
                     kind:QONRemoteConfigV2TransportFailureKindSnapshotMalformed
               statusCode:@(status)
                   retryAfterMilliseconds:nil];
        return;
      }
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
      [self bootstrapForScope:scope
                   generation:generation
                       refuse:[self fetchRefusalForRespond:respond]
                   completion:^(QONRemoteConfigV2GatewaySession *freshSession) {
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
  // Built through NSURLComponents so a base URL carrying a query or fragment
  // cannot swallow the route path.
  NSURLComponents *components = [NSURLComponents componentsWithURL:self.baseURL
                                          resolvingAgainstBaseURL:YES];
  if (!components || !body) return nil;
  NSString *basePath = components.percentEncodedPath ?: @"";
  if (![basePath hasSuffix:@"/"]) basePath = [basePath stringByAppendingString:@"/"];
  components.percentEncodedPath = [basePath stringByAppendingString:path];
  components.percentEncodedQuery = nil;
  components.percentEncodedFragment = nil;
  NSURL *url = components.URL;
  if (!url) return nil;

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
  NSString *value = QONRemoteConfigV2HeaderValue(response, @"Retry-After");
  if (value.length == 0) return nil;
  NSScanner *scanner = [NSScanner scannerWithString:value];
  long long seconds = 0;
  // The coordinator lets Retry-After override its own backoff unconditionally,
  // so a zero delay must read as "absent" rather than "retry immediately".
  if (![scanner scanLongLong:&seconds] || !scanner.isAtEnd || seconds <= 0) return nil;
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
