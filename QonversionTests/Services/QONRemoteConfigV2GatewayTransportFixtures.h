//
//  Shared deterministic fakes for the Remote Config v2 gateway transport.
//
//  The file carries implementations on purpose so the XCTest suite and the
//  headless harness can share exactly one set of fakes. Include it from a
//  single translation unit per target.
//

#import <Foundation/Foundation.h>

#import "QONRemoteConfigV2GatewayTransport.h"
#import "QNLocalStorage.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Scripted HTTP

@interface QONRCV2ScriptedHTTPResponse : NSObject
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, strong, nullable) NSData *body;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, assign) BOOL isTransportError;
+ (instancetype)status:(NSInteger)status
                  body:(nullable NSData *)body
               headers:(nullable NSDictionary<NSString *, NSString *> *)headers;
+ (instancetype)transportError;
@end

@implementation QONRCV2ScriptedHTTPResponse
+ (instancetype)status:(NSInteger)status
                  body:(nullable NSData *)body
               headers:(nullable NSDictionary<NSString *, NSString *> *)headers {
  QONRCV2ScriptedHTTPResponse *response = [QONRCV2ScriptedHTTPResponse new];
  response.status = status;
  response.body = body;
  response.headers = headers;
  return response;
}
+ (instancetype)transportError {
  QONRCV2ScriptedHTTPResponse *response = [QONRCV2ScriptedHTTPResponse new];
  response.isTransportError = YES;
  return response;
}
@end

@interface QONRCV2FakeHTTPExecutor : NSObject <QONRemoteConfigV2HTTPExecuting>
@property (nonatomic, strong) NSMutableArray<QONRCV2ScriptedHTTPResponse *> *script;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
- (void)enqueue:(QONRCV2ScriptedHTTPResponse *)response;
@end

@implementation QONRCV2FakeHTTPExecutor
- (instancetype)init {
  self = [super init];
  if (self) {
    _script = [NSMutableArray new];
    _requests = [NSMutableArray new];
  }
  return self;
}
- (void)enqueue:(QONRCV2ScriptedHTTPResponse *)response {
  [self.script addObject:response];
}
- (void)executeRequest:(NSURLRequest *)request
            completion:(QONRemoteConfigV2HTTPCompletion)completion {
  [self.requests addObject:request];
  QONRCV2ScriptedHTTPResponse *scripted = self.script.firstObject;
  if (scripted) [self.script removeObjectAtIndex:0];
  if (!scripted || scripted.isTransportError) {
    completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorNotConnectedToInternet
                                         userInfo:nil]);
    return;
  }
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                           statusCode:scripted.status
                                                          HTTPVersion:@"HTTP/1.1"
                                                         headerFields:scripted.headers];
  completion(scripted.body, response, nil);
}
@end

#pragma mark - Storage and clock

@interface QONRCV2FakeLocalStorage : NSObject <QNLocalStorage>
@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, assign) BOOL ignoreWrites;
@end

@implementation QONRCV2FakeLocalStorage
- (instancetype)init {
  self = [super init];
  if (self) _objects = [NSMutableDictionary new];
  return self;
}
- (void)storeObject:(id)object forKey:(NSString *)key {
  if (!self.ignoreWrites) self.objects[key] = object;
}
- (id)loadObjectForKey:(NSString *)key { return self.objects[key]; }
- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion(self.objects[key]);
}
- (void)removeObjectForKey:(NSString *)key { [self.objects removeObjectForKey:key]; }
@end

@interface QONRCV2FakeClock : NSObject <QONRemoteConfigV2FetchClock>
@property (nonatomic, assign) int64_t now;
@end

@implementation QONRCV2FakeClock
- (int64_t)nowMilliseconds { return self.now; }
@end

#pragma mark - Client context

@interface QONRCV2FakeInstallDateProvider : NSObject <QONRemoteConfigV2DeviceInstallDateProviding>
@property (nonatomic, strong, nullable) NSNumber *seconds;
@end

@implementation QONRCV2FakeInstallDateProvider
- (nullable NSNumber *)deviceInstalledAtSeconds { return self.seconds; }
@end

#pragma mark - Builders

static NSString *const QONRCV2TestProjectToken = @"project-token-secret";
static NSString *const QONRCV2TestBaseURLString = @"https://gateway.test.example/";
static NSString *const QONRCV2TestAnonUID = @"anon-uid-1";
static NSString *const QONRCV2TestStrongETag =
    @"\"0000000000000000000000000000000000000000000000000000000000000001\"";

static QONRemoteConfigV2Scope *QONRCV2Scope(NSString *canonicalUserID) {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:@"project-key"
                                                environment:@"production"
                                            canonicalUserID:canonicalUserID];
}

static QONRemoteConfigV2DeviceClientContextProvider *QONRCV2ContextProvider(
    id<QONRemoteConfigV2DeviceInstallDateProviding> installDateProvider) {
  return [[QONRemoteConfigV2DeviceClientContextProvider alloc]
        initWithPlatform:@"iOS"
              appVersion:@"1.2.3"
               osVersion:@"17.4"
              sdkVersion:@"9.9.9"
                  locale:@"en_US"
             deviceModel:@"iPhone15,2"
     installDateProvider:installDateProvider];
}

/** The project id every fixture bootstrap states unless a test says otherwise. */
static int64_t const QONRCV2TestProjectID = 42;

static NSData *QONRCV2BootstrapBodyForProject(NSString *token, int64_t expiresAtSeconds,
                                              int64_t projectID) {
  NSString *json = [NSString stringWithFormat:
      @"{\"session_token\":\"%@\",\"project_id\":%lld,\"environment\":\"production\","
       "\"expires_at\":%lld}", token, projectID, expiresAtSeconds];
  return [json dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *QONRCV2BootstrapBody(NSString *token, int64_t expiresAtSeconds) {
  return QONRCV2BootstrapBodyForProject(token, expiresAtSeconds, QONRCV2TestProjectID);
}

/**
 Deliberately non-canonical: unsorted keys, irregular whitespace and an escaped
 unicode sequence. Any re-serialization on the way to admission changes it.
 */
static NSData *QONRCV2NonCanonicalSnapshotBody(void) {
  NSString *json = @"{  \"schema\" : 1,\n  \"z_key\":\"\\u00e9\",\r\n"
                    "\"entries\" : [ { \"key\" :\"a\" } ] ,\"a_key\":  2.500 }";
  return [json dataUsingEncoding:NSUTF8StringEncoding];
}

static id QONRCV2JSONFromRequest(NSURLRequest *request) {
  if (!request.HTTPBody) return nil;
  return [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
}

static NSString *_Nullable QONRCV2Header(NSURLRequest *request, NSString *field) {
  return [request valueForHTTPHeaderField:field];
}

static BOOL QONRCV2DataIdenticalBytes(NSData *_Nullable left, NSData *_Nullable right) {
  if (!left || !right) return NO;
  if (left.length != right.length) return NO;
  return memcmp(left.bytes, right.bytes, left.length) == 0;
}

#pragma mark - Activation ack

static NSString *const QONRCV2SeededSessionToken = @"qrcs1.seeded-session";
static NSString *const QONRCV2MintedSessionToken = @"qrcs1.session";
static int64_t const QONRCV2AckRelease7 = 7;
static int64_t const QONRCV2AckRelease9 = 9;
static int64_t const QONRCV2AckActivatedAtSeconds = 1700000000;
static int64_t const QONRCV2AckLaterActivatedAtSeconds = 1700000900;

/**
 Answers by path, so an ack and a bootstrap are never order-coupled.

 The FIFO QONRCV2FakeHTTPExecutor cannot express "every ack is a 404 but the
 session route always works", which is exactly the rollout state the ack has to
 survive.
 */
@interface QONRCV2ScriptedGateway : NSObject <QONRemoteConfigV2HTTPExecuting>
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *ackRequests;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *sessionRequests;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *ackStatuses;
/** Accepts the ack and never answers it. */
@property (nonatomic, assign) BOOL hangAcks;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *telemetryRequests;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *telemetryStatuses;
/** Accepts the telemetry batch and never answers it. */
@property (nonatomic, assign) BOOL hangTelemetry;
- (void)scriptAckStatus:(NSInteger)status;
- (void)scriptAckStatus:(NSInteger)status times:(NSUInteger)times;
- (void)scriptTelemetryStatus:(NSInteger)status;
- (void)scriptTelemetryStatus:(NSInteger)status times:(NSUInteger)times;
- (NSUInteger)telemetryRequestCount;
@end

@implementation QONRCV2ScriptedGateway
- (instancetype)init {
  self = [super init];
  if (self) {
    _ackRequests = [NSMutableArray new];
    _sessionRequests = [NSMutableArray new];
    _ackStatuses = [NSMutableArray new];
    _telemetryRequests = [NSMutableArray new];
    _telemetryStatuses = [NSMutableArray new];
  }
  return self;
}
- (void)scriptAckStatus:(NSInteger)status {
  [self scriptAckStatus:status times:1];
}
- (void)scriptAckStatus:(NSInteger)status times:(NSUInteger)times {
  @synchronized (self) {
    for (NSUInteger index = 0; index < times; index++) [self.ackStatuses addObject:@(status)];
  }
}
- (void)scriptTelemetryStatus:(NSInteger)status {
  [self scriptTelemetryStatus:status times:1];
}
- (void)scriptTelemetryStatus:(NSInteger)status times:(NSUInteger)times {
  @synchronized (self) {
    for (NSUInteger index = 0; index < times; index++) {
      [self.telemetryStatuses addObject:@(status)];
    }
  }
}
- (NSUInteger)telemetryRequestCount {
  @synchronized (self) {
    return self.telemetryRequests.count;
  }
}
- (void)executeRequest:(NSURLRequest *)request
            completion:(QONRemoteConfigV2HTTPCompletion)completion {
  NSString *path = request.URL.path ?: @"";
  if ([path hasSuffix:QONRemoteConfigV2GatewaySessionPath]) {
    NSUInteger ordinal = 0;
    @synchronized (self) {
      [self.sessionRequests addObject:request];
      ordinal = self.sessionRequests.count;
    }
    NSString *token = ordinal == 1
        ? QONRCV2MintedSessionToken
        : [NSString stringWithFormat:@"%@-%lu", QONRCV2MintedSessionToken, (unsigned long)ordinal];
    completion(QONRCV2BootstrapBody(token, 0),
               [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                           statusCode:200
                                          HTTPVersion:@"HTTP/1.1"
                                         headerFields:nil],
               nil);
    return;
  }
  if ([path hasSuffix:QONRemoteConfigV2GatewayAckPath]) {
    NSInteger status = 204;
    @synchronized (self) {
      [self.ackRequests addObject:request];
      if (self.hangAcks) return;
      if (self.ackStatuses.count > 0) {
        status = self.ackStatuses.firstObject.integerValue;
        [self.ackStatuses removeObjectAtIndex:0];
      }
    }
    completion(nil,
               [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                           statusCode:status
                                          HTTPVersion:@"HTTP/1.1"
                                         headerFields:nil],
               nil);
    return;
  }
  if ([path hasSuffix:QONRemoteConfigV2GatewayTelemetryPath]) {
    NSInteger status = 204;
    @synchronized (self) {
      [self.telemetryRequests addObject:request];
      if (self.hangTelemetry) return;
      if (self.telemetryStatuses.count > 0) {
        status = self.telemetryStatuses.firstObject.integerValue;
        [self.telemetryStatuses removeObjectAtIndex:0];
      }
    }
    completion(nil,
               [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                           statusCode:status
                                          HTTPVersion:@"HTTP/1.1"
                                         headerFields:nil],
               nil);
    return;
  }
  completion(nil,
             [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                         statusCode:404
                                        HTTPVersion:@"HTTP/1.1"
                                       headerFields:nil],
             nil);
}
@end

@interface QONRCV2ManualTask : NSObject <QONRemoteConfigV2FetchScheduledTask>
@property (nonatomic, copy, nullable) dispatch_block_t action;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation QONRCV2ManualTask
- (void)cancel {
  @synchronized (self) {
    self.cancelled = YES;
    self.action = nil;
  }
}
@end

/** Manual retry clock: a bounded ladder can be walked without ever sleeping. */
@interface QONRCV2ManualScheduler : NSObject <QONRemoteConfigV2FetchScheduler>
@property (nonatomic, strong) NSMutableArray<QONRCV2ManualTask *> *tasks;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *requestedDelays;
- (NSUInteger)pendingCount;
- (BOOL)runAll;
@end

@implementation QONRCV2ManualScheduler
- (instancetype)init {
  self = [super init];
  if (self) {
    _tasks = [NSMutableArray new];
    _requestedDelays = [NSMutableArray new];
  }
  return self;
}
- (id<QONRemoteConfigV2FetchScheduledTask>)scheduleAfterMilliseconds:(int64_t)delay
                                                              action:(dispatch_block_t)action {
  QONRCV2ManualTask *task = [QONRCV2ManualTask new];
  task.action = action;
  @synchronized (self) {
    [self.requestedDelays addObject:@(delay)];
    [self.tasks addObject:task];
  }
  return task;
}
- (NSUInteger)pendingCount {
  NSUInteger count = 0;
  @synchronized (self) {
    for (QONRCV2ManualTask *task in self.tasks) {
      @synchronized (task) {
        if (!task.cancelled && task.action) count += 1;
      }
    }
  }
  return count;
}
- (BOOL)runAll {
  NSArray<QONRCV2ManualTask *> *snapshot = nil;
  @synchronized (self) {
    snapshot = [self.tasks copy];
    [self.tasks removeAllObjects];
  }
  BOOL ran = NO;
  for (QONRCV2ManualTask *task in snapshot) {
    dispatch_block_t action = nil;
    @synchronized (task) {
      if (task.cancelled) continue;
      action = task.action;
      task.action = nil;
    }
    if (action) {
      action();
      ran = YES;
    }
  }
  return ran;
}
@end

@interface QONRCV2FixedRandom : NSObject <QONRemoteConfigV2FetchRandom>
@end

@implementation QONRCV2FixedRandom
- (double)nextUnitInterval { return 0.5; }
@end

/**
 The shipped transport under the shipped ack sender.

 Only three things are doubles: the HTTP executor, the retry scheduler (manual,
 so a bounded ladder needs no sleeping) and the jitter source. The durable ack
 store is the real one, over an in-memory QNLocalStorage, so a "restart" can
 re-create it and prove the record really is durable.
 */
@interface QONRCV2AckEnvironment : NSObject
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2TelemetrySender *> *telemetrySenders;
@property (nonatomic, strong) QONRCV2ScriptedGateway *gateway;
@property (nonatomic, strong) QONRCV2FakeLocalStorage *storage;
@property (nonatomic, strong) QONRemoteConfigV2GatewaySessionStore *sessionStore;
@property (nonatomic, strong) QONRemoteConfigV2ProjectIdentityStore *projectIdentityStore;
@property (nonatomic, strong) QONRCV2FakeClock *clock;
@property (nonatomic, strong) QONRemoteConfigV2GatewayTransport *transport;
@property (nonatomic, strong) QONRCV2ManualScheduler *scheduler;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2ActivationAckSender *> *senders;
- (QONRemoteConfigV2ActivationAckSender *)makeSender;
/** A telemetry sender over the same transport, storage and manual scheduler. */
- (QONRemoteConfigV2TelemetrySender *)makeTelemetrySender;
- (QONRemoteConfigV2TelemetrySender *)makeTelemetrySenderWithFlushThreshold:
    (NSUInteger)flushThreshold;
- (void)useIdentityScope:(nullable QONRemoteConfigV2Scope *)scope;
- (nullable QONRemoteConfigV2ActivationAckRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope;
- (nullable QONRemoteConfigV2TelemetryRecord *)telemetryRecordForScope:
    (QONRemoteConfigV2Scope *)scope;
- (void)settle;
@end

@implementation QONRCV2AckEnvironment

- (instancetype)init {
  self = [super init];
  if (self) {
    _gateway = [QONRCV2ScriptedGateway new];
    _storage = [QONRCV2FakeLocalStorage new];
    _sessionStore = [[QONRemoteConfigV2GatewaySessionStore alloc] initWithLocalStorage:_storage];
    _projectIdentityStore = [[QONRemoteConfigV2ProjectIdentityStore alloc]
        initWithLocalStorage:_storage
                     baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                projectToken:QONRCV2TestProjectToken];
    _clock = [QONRCV2FakeClock new];
    _clock.now = QONRCV2AckActivatedAtSeconds * 1000;
    _scheduler = [QONRCV2ManualScheduler new];
    _senders = [NSMutableArray new];
    _telemetrySenders = [NSMutableArray new];
    _transport = [[QONRemoteConfigV2GatewayTransport alloc]
         initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
            projectToken:QONRCV2TestProjectToken
            httpExecutor:_gateway
            sessionStore:_sessionStore
    projectIdentityStore:_projectIdentityStore
   clientContextProvider:QONRCV2ContextProvider([QONRCV2FakeInstallDateProvider new])
                   clock:_clock
         failureObserver:nil];
    // An ack can only ever follow a snapshot read, so the realistic starting
    // state is a session this installation already holds — which is also the
    // state that licenses the single re-bootstrap on a 401.
    for (NSString *uid in @[@"anon-uid-a", @"anon-uid-b"]) {
      QONRemoteConfigV2Scope *scope = QONRCV2Scope(uid);
      [_projectIdentityStore establishProjectID:QONRCV2TestProjectID forScope:scope];
      [_sessionStore storeSession:[[QONRemoteConfigV2GatewaySession alloc]
                                      initWithSessionToken:QONRCV2SeededSessionToken
                                                 projectID:QONRCV2TestProjectID
                                               environment:@"production"
                                          expiresAtSeconds:0]
                         forScope:scope];
    }
    [_transport updateScope:QONRCV2Scope(@"anon-uid-a")];
  }
  return self;
}

/** A sender over a freshly built store: a new process, the same durable state. */
- (QONRemoteConfigV2ActivationAckSender *)makeSender {
  QONRemoteConfigV2ActivationAckSender *sender = [[QONRemoteConfigV2ActivationAckSender alloc]
      initWithTransport:self.transport
                  store:[[QONRemoteConfigV2ActivationAckStore alloc]
                            initWithLocalStorage:self.storage]
                  clock:self.clock
                 random:[QONRCV2FixedRandom new]
              scheduler:self.scheduler
                  queue:dispatch_queue_create("io.qonversion.rc-ack-test", DISPATCH_QUEUE_SERIAL)];
  if (sender) [self.senders addObject:sender];
  return sender;
}

/** A telemetry sender over a freshly built store: a new process, the same disk. */
- (QONRemoteConfigV2TelemetrySender *)makeTelemetrySender {
  QONRemoteConfigV2TelemetrySender *sender = [[QONRemoteConfigV2TelemetrySender alloc]
      initWithTransport:self.transport
                  store:[[QONRemoteConfigV2TelemetryStore alloc]
                            initWithLocalStorage:self.storage]
                  clock:self.clock
                 random:[QONRCV2FixedRandom new]
              scheduler:self.scheduler
                  queue:dispatch_queue_create("io.qonversion.rc-telemetry-test",
                                              DISPATCH_QUEUE_SERIAL)];
  if (sender) [self.telemetrySenders addObject:sender];
  return sender;
}

/** The same, with the flush threshold raised so a test can choose the moment. */
- (QONRemoteConfigV2TelemetrySender *)makeTelemetrySenderWithFlushThreshold:
    (NSUInteger)flushThreshold {
  QONRemoteConfigV2TelemetrySender *sender = [[QONRemoteConfigV2TelemetrySender alloc]
          initWithTransport:self.transport
                      store:[[QONRemoteConfigV2TelemetryStore alloc]
                                initWithLocalStorage:self.storage]
                      clock:self.clock
                     random:[QONRCV2FixedRandom new]
                  scheduler:self.scheduler
                      queue:dispatch_queue_create("io.qonversion.rc-telemetry-test",
                                                  DISPATCH_QUEUE_SERIAL)
            maximumAttempts:QONRemoteConfigV2TelemetryMaximumAttempts
initialRetryDelayMilliseconds:QONRemoteConfigV2TelemetryInitialRetryDelayMilliseconds
maximumRetryDelayMilliseconds:QONRemoteConfigV2TelemetryMaximumRetryDelayMilliseconds
             maximumEntries:QONRemoteConfigV2TelemetryMaximumEntries
             flushThreshold:flushThreshold
  flushIntervalMilliseconds:QONRemoteConfigV2TelemetryFlushIntervalMilliseconds];
  if (sender) [self.telemetrySenders addObject:sender];
  return sender;
}

- (void)useIdentityScope:(nullable QONRemoteConfigV2Scope *)scope {
  [self.transport updateScope:scope];
}

- (nullable QONRemoteConfigV2ActivationAckRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope {
  return [[[QONRemoteConfigV2ActivationAckStore alloc] initWithLocalStorage:self.storage]
      recordForScope:scope];
}

- (nullable QONRemoteConfigV2TelemetryRecord *)telemetryRecordForScope:
    (QONRemoteConfigV2Scope *)scope {
  return [[[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:self.storage]
      recordForScope:scope];
}

/**
 Runs every unit of ack work that is already owed.

 A response is handed back inside the block that sent it, so it lands on the
 sender's queue behind the barrier this method just posted: one pass is never
 enough to reach quiescence.
 */
- (void)settle {
  for (NSUInteger pass = 0; pass < 8; pass++) {
    for (QONRemoteConfigV2ActivationAckSender *sender in [self.senders copy]) {
      [sender settleForTesting];
    }
    for (QONRemoteConfigV2TelemetrySender *sender in [self.telemetrySenders copy]) {
      [sender settleForTesting];
    }
  }
}

@end

/** The one ack scope every fixture uses, and the identity it is never confused with. */
static QONRemoteConfigV2Scope *QONRCV2AckScopeA(void) { return QONRCV2Scope(@"anon-uid-a"); }
static QONRemoteConfigV2Scope *QONRCV2AckScopeB(void) { return QONRCV2Scope(@"anon-uid-b"); }

/** The release number an ack request states, or 0 when the body says nothing. */
static int64_t QONRCV2AckReleaseNumber(NSURLRequest *request) {
  id body = QONRCV2JSONFromRequest(request);
  if (![body isKindOfClass:NSDictionary.class]) return 0;
  id value = ((NSDictionary *)body)[@"release_number"];
  return [value isKindOfClass:NSNumber.class] ? [value longLongValue] : 0;
}

#pragma mark - Client telemetry

static NSString *const QONRCV2TelemetryKeyAlpha = @"paywall_prices";
static NSString *const QONRCV2TelemetryKeyBeta = @"onboarding_copy";
static int64_t const QONRCV2TelemetryRelease4 = 4;
static int64_t const QONRCV2TelemetryObservedAtSeconds = 1700000000;

/** The `events` array a telemetry request states, or nil when it states none. */
static NSArray *_Nullable QONRCV2TelemetryEvents(NSURLRequest *request) {
  id body = QONRCV2JSONFromRequest(request);
  if (![body isKindOfClass:NSDictionary.class]) return nil;
  id events = ((NSDictionary *)body)[@"events"];
  return [events isKindOfClass:NSArray.class] ? events : nil;
}

/** The single event of a one-event batch, or nil when the batch is not one event. */
static NSDictionary *_Nullable QONRCV2TelemetryOnlyEvent(NSURLRequest *request) {
  NSArray *events = QONRCV2TelemetryEvents(request);
  if (events.count != 1) return nil;
  id event = events.firstObject;
  return [event isKindOfClass:NSDictionary.class] ? event : nil;
}

@interface QONRCV2RecordedTelemetryBatch : NSObject
@property (nonatomic, strong) QONRemoteConfigV2Scope *scope;
@property (nonatomic, copy) NSArray<QONRemoteConfigV2TelemetryEvent *> *events;
@end

@implementation QONRCV2RecordedTelemetryBatch
@end

/**
 Scripted telemetry transport for the sender's own rules.

 The route tests drive the real transport instead; this one exists so
 coalescing, bounds and the retry ladder can be exercised without a gateway in
 the way.
 */
@interface QONRCV2FakeTelemetryTransport : NSObject <QONRemoteConfigV2TelemetryTransporting>
@property (nonatomic, strong) NSMutableArray<QONRCV2RecordedTelemetryBatch *> *batches;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *responses;
/** Accepts the batch and never answers it. */
@property (nonatomic, assign) BOOL hang;
- (void)scriptResponse:(QONRemoteConfigV2TelemetryResponse)response times:(NSUInteger)times;
- (NSUInteger)batchCount;
- (nullable QONRCV2RecordedTelemetryBatch *)lastBatch;
/** Every event of every batch, in the order the sender shipped them. */
- (NSArray<QONRemoteConfigV2TelemetryEvent *> *)allEvents;
@end

@implementation QONRCV2FakeTelemetryTransport
- (instancetype)init {
  self = [super init];
  if (self) {
    _batches = [NSMutableArray new];
    _responses = [NSMutableArray new];
  }
  return self;
}
- (void)scriptResponse:(QONRemoteConfigV2TelemetryResponse)response times:(NSUInteger)times {
  @synchronized (self) {
    for (NSUInteger index = 0; index < times; index++) [self.responses addObject:@(response)];
  }
}
- (NSUInteger)batchCount {
  @synchronized (self) {
    return self.batches.count;
  }
}
- (nullable QONRCV2RecordedTelemetryBatch *)lastBatch {
  @synchronized (self) {
    return self.batches.lastObject;
  }
}
- (NSArray<QONRemoteConfigV2TelemetryEvent *> *)allEvents {
  NSMutableArray<QONRemoteConfigV2TelemetryEvent *> *events = [NSMutableArray new];
  @synchronized (self) {
    for (QONRCV2RecordedTelemetryBatch *batch in self.batches) {
      [events addObjectsFromArray:batch.events];
    }
  }
  return events;
}
- (void)sendTelemetryBatch:(NSArray<QONRemoteConfigV2TelemetryEvent *> *)events
                   forScope:(QONRemoteConfigV2Scope *)scope
                 completion:(QONRemoteConfigV2TelemetryCompletion)completion {
  QONRemoteConfigV2TelemetryResponse response = QONRemoteConfigV2TelemetryResponseDelivered;
  @synchronized (self) {
    QONRCV2RecordedTelemetryBatch *recorded = [QONRCV2RecordedTelemetryBatch new];
    recorded.scope = scope;
    recorded.events = events;
    [self.batches addObject:recorded];
    if (self.hang) return;
    if (self.responses.count > 0) {
      response = (QONRemoteConfigV2TelemetryResponse)self.responses.firstObject.integerValue;
      [self.responses removeObjectAtIndex:0];
    }
  }
  completion(response);
}
@end

/**
 A telemetry sender over the fake transport, the real durable store and a manual
 scheduler, with the bounds the caller wants to exercise.
 */
@interface QONRCV2TelemetryEnvironment : NSObject
@property (nonatomic, strong) QONRCV2FakeTelemetryTransport *transport;
@property (nonatomic, strong) QONRCV2FakeLocalStorage *storage;
@property (nonatomic, strong) QONRCV2FakeClock *clock;
@property (nonatomic, strong) QONRCV2ManualScheduler *scheduler;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2TelemetrySender *> *senders;
- (QONRemoteConfigV2TelemetrySender *)makeSenderWithMaximumEntries:(NSUInteger)maximumEntries
                                                    flushThreshold:(NSUInteger)flushThreshold;
- (QONRemoteConfigV2TelemetrySender *)makeSender;
- (nullable QONRemoteConfigV2TelemetryRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope;
- (void)settle;
@end

@implementation QONRCV2TelemetryEnvironment

- (instancetype)init {
  self = [super init];
  if (self) {
    _transport = [QONRCV2FakeTelemetryTransport new];
    _storage = [QONRCV2FakeLocalStorage new];
    _clock = [QONRCV2FakeClock new];
    _clock.now = QONRCV2TelemetryObservedAtSeconds * 1000;
    _scheduler = [QONRCV2ManualScheduler new];
    _senders = [NSMutableArray new];
  }
  return self;
}

- (QONRemoteConfigV2TelemetrySender *)makeSenderWithMaximumEntries:(NSUInteger)maximumEntries
                                                    flushThreshold:(NSUInteger)flushThreshold {
  QONRemoteConfigV2TelemetrySender *sender = [[QONRemoteConfigV2TelemetrySender alloc]
        initWithTransport:self.transport
                    store:[[QONRemoteConfigV2TelemetryStore alloc]
                              initWithLocalStorage:self.storage]
                    clock:self.clock
                   random:[QONRCV2FixedRandom new]
                scheduler:self.scheduler
                    queue:dispatch_queue_create("io.qonversion.rc-telemetry-unit",
                                                DISPATCH_QUEUE_SERIAL)
          maximumAttempts:QONRemoteConfigV2TelemetryMaximumAttempts
initialRetryDelayMilliseconds:QONRemoteConfigV2TelemetryInitialRetryDelayMilliseconds
maximumRetryDelayMilliseconds:QONRemoteConfigV2TelemetryMaximumRetryDelayMilliseconds
           maximumEntries:maximumEntries
           flushThreshold:flushThreshold
flushIntervalMilliseconds:QONRemoteConfigV2TelemetryFlushIntervalMilliseconds];
  if (sender) [self.senders addObject:sender];
  return sender;
}

- (QONRemoteConfigV2TelemetrySender *)makeSender {
  return [self makeSenderWithMaximumEntries:QONRemoteConfigV2TelemetryMaximumEntries
                             flushThreshold:QONRemoteConfigV2TelemetryFlushThreshold];
}

- (nullable QONRemoteConfigV2TelemetryRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope {
  return [[[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:self.storage]
      recordForScope:scope];
}

/**
 Runs every unit of telemetry work that is already owed.

 A response is handed back inside the block that sent it, so it lands on the
 sender's queue behind the barrier this method just posted: one pass is never
 enough to reach quiescence.
 */
- (void)settle {
  for (NSUInteger pass = 0; pass < 8; pass++) {
    for (QONRemoteConfigV2TelemetrySender *sender in [self.senders copy]) {
      [sender settleForTesting];
    }
  }
}

@end

/** Records one decode failure the given number of times. */
static void QONRCV2RecordDecodeFailures(QONRemoteConfigV2TelemetrySender *sender,
                                        NSString *logicalKey, int64_t releaseNumber,
                                        NSUInteger times) {
  for (NSUInteger index = 0; index < times; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:logicalKey
         releaseNumber:releaseNumber];
  }
}

NS_ASSUME_NONNULL_END
