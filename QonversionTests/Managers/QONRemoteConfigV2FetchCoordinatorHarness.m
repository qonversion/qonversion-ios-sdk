#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2FetchPolicyStore.h"
#import "QNLocalStorage.h"

// The harness links only the fetch-policy slice. The full SDK owns this parser helper.
id QONRemoteConfigPortableJSONObject(__unused NSData *data, __unused NSUInteger maximumBytes) {
  return @{};
}

static NSUInteger failures = 0;
static NSUInteger checks = 0;
#define QON_CHECK(condition, message) do { checks += 1; if (!(condition)) { \
  failures += 1; fprintf(stderr, "FAIL: %s\n", message); } } while (0)

@interface HarnessTask : NSObject <QONRemoteConfigV2FetchScheduledTask>
@property(nonatomic, copy) dispatch_block_t action;
@property(nonatomic) BOOL cancelled;
@end
@implementation HarnessTask
- (void)cancel { self.cancelled = YES; }
@end

@interface HarnessScheduler : NSObject <QONRemoteConfigV2FetchScheduler>
@property(nonatomic, strong) NSMutableArray<HarnessTask *> *tasks;
@property(nonatomic) BOOL throws;
- (void)fire:(NSUInteger)index;
@end
@implementation HarnessScheduler
- (instancetype)init { self = [super init]; if (self) _tasks = [NSMutableArray new]; return self; }
- (id<QONRemoteConfigV2FetchScheduledTask>)scheduleAfterMilliseconds:(__unused int64_t)delay
                                                              action:(dispatch_block_t)action {
  if (self.throws) @throw [NSException exceptionWithName:@"scheduler" reason:nil userInfo:nil];
  HarnessTask *task = [HarnessTask new]; task.action = action; [self.tasks addObject:task]; return task;
}
- (void)fire:(NSUInteger)index { HarnessTask *task = self.tasks[index]; if (!task.cancelled) task.action(); }
@end

@interface HarnessClock : NSObject <QONRemoteConfigV2FetchClock>
@property(nonatomic) int64_t now;
@end
@implementation HarnessClock
- (int64_t)nowMilliseconds { return self.now; }
@end

@interface HarnessRandom : NSObject <QONRemoteConfigV2FetchRandom>
@property(nonatomic) double value;
@end
@implementation HarnessRandom
- (double)nextUnitInterval { return self.value; }
@end

@interface HarnessStore : NSObject <QONRemoteConfigV2FetchPolicyStoring>
@property(nonatomic, strong) NSMutableDictionary *states;
@property(nonatomic) BOOL saveSucceeds;
@property(nonatomic) BOOL throwsOnLoad;
@property(nonatomic, strong) NSNumber *forcedLoadStatus;
@end
@implementation HarnessStore
- (instancetype)init { self = [super init]; if (self) { _states = [NSMutableDictionary new]; _saveSucceeds = YES; } return self; }
- (NSString *)key:(QONRemoteConfigV2FetchPolicyScope *)scope {
  return [NSString stringWithFormat:@"%@/%@", scope.projectKey, scope.environment];
}
- (QONRemoteConfigV2FetchPolicyLoadResult *)loadResultForScope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  if (self.throwsOnLoad) @throw [NSException exceptionWithName:@"load" reason:nil userInfo:nil];
  if (self.forcedLoadStatus) {
    return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
        initWithStatus:self.forcedLoadStatus.integerValue state:nil];
  }
  QONRemoteConfigV2FetchPolicyState *state = self.states[[self key:scope]];
  return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
      initWithStatus:state ? QONRemoteConfigV2FetchPolicyLoadStatusFound
                         : QONRemoteConfigV2FetchPolicyLoadStatusMissing
               state:state];
}
- (BOOL)saveState:(QONRemoteConfigV2FetchPolicyState *)state forScope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  if (!self.saveSucceeds) return NO; self.states[[self key:scope]] = state; return YES;
}
@end

@interface HarnessLocalStorage : NSObject <QNLocalStorage>
@property(nonatomic, strong) NSMutableDictionary *objects;
@property(nonatomic) BOOL ignoreWrites;
@property(nonatomic) BOOL throwsOnRead;
@end
@implementation HarnessLocalStorage
- (instancetype)init { self = [super init]; if (self) _objects = [NSMutableDictionary new]; return self; }
- (void)storeObject:(id)object forKey:(NSString *)key { if (!self.ignoreWrites) self.objects[key] = object; }
- (id)loadObjectForKey:(NSString *)key {
  if (self.throwsOnRead) @throw [NSException exceptionWithName:@"read" reason:nil userInfo:nil];
  return self.objects[key];
}
- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion { completion(self.objects[key]); }
- (void)removeObjectForKey:(NSString *)key { [self.objects removeObjectForKey:key]; }
@end

@interface HarnessTransport : NSObject <QONRemoteConfigV2FetchTransport>
@property(nonatomic, strong) NSMutableArray *requests;
@property(nonatomic, strong) NSMutableArray *completions;
@property(nonatomic) BOOL throws;
- (void)complete:(NSUInteger)index response:(QONRemoteConfigV2FetchResponse *)response;
@end
@implementation HarnessTransport
- (instancetype)init { self = [super init]; if (self) { _requests = [NSMutableArray new]; _completions = [NSMutableArray new]; } return self; }
- (void)fetchRequest:(QONRemoteConfigV2FetchRequest *)request completion:(QONRemoteConfigV2FetchTransportCompletion)completion {
  if (self.throws) @throw [NSException exceptionWithName:@"transport" reason:nil userInfo:nil];
  [self.requests addObject:request]; [self.completions addObject:[completion copy]];
}
- (void)complete:(NSUInteger)index response:(QONRemoteConfigV2FetchResponse *)response {
  QONRemoteConfigV2FetchTransportCompletion completion = self.completions[index]; completion(response);
}
@end

@interface HarnessCore : NSObject <QONRemoteConfigV2FetchCore>
@property(nonatomic, strong) QONRemoteConfigV2Scope *scope;
@property(nonatomic, strong) QONRemoteConfigV2ConditionalRequestValidator *validator;
@property(nonatomic, strong) QONRemoteConfigSnapshot *snapshot;
@property(nonatomic) NSUInteger admissions;
@property(nonatomic) NSUInteger admittedBodies;
@property(nonatomic) int64_t lastAdmittedProjectID;
@property(nonatomic) QONRemoteConfigV2TransitionStatus transitionStatus;
@end
@implementation HarnessCore
- (void)setScope:(QONRemoteConfigV2Scope *)scope { _scope = scope; }
- (QONRemoteConfigSnapshot *)unguardedSnapshot { return self.snapshot; }
- (QONRemoteConfigV2AdmissionToken *)beginAdmissionForScope:(__unused QONRemoteConfigV2Scope *)scope {
  self.admissions += 1; return (id)[NSObject new];
}
- (QONRemoteConfigV2TransitionStatus)admitBody:(__unused NSData *)body
                                   strongETag:(__unused NSString *)strongETag
                                    projectID:(int64_t)projectID
                               admissionToken:(__unused QONRemoteConfigV2AdmissionToken *)admissionToken {
  self.admittedBodies += 1; self.lastAdmittedProjectID = projectID; return self.transitionStatus;
}
- (QONRemoteConfigV2ConditionalRequestValidator *)conditionalRequestValidator { return self.validator; }
- (BOOL)isConditionalRequestValidatorCurrent:(QONRemoteConfigV2ConditionalRequestValidator *)validator {
  return [self.validator isEqual:validator];
}
@end

static QONRemoteConfigV2FetchBinding *Binding(NSString *user) {
  QONRemoteConfigV2Scope *scope = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:user];
  return [[QONRemoteConfigV2FetchBinding alloc] initWithScope:scope];
}

static QONRemoteConfigV2FetchPolicy *Policy(int64_t minimum, NSNumber *timeout) {
  return [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:minimum timeoutMilliseconds:timeout
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000];
}

static QONRemoteConfigV2FetchCoordinator *Coordinator(HarnessCore *core, HarnessTransport *transport,
    id<QONRemoteConfigV2FetchPolicyStoring> store, HarnessClock *clock, HarnessRandom *random,
    HarnessScheduler *scheduler,
    QONRemoteConfigV2FetchPolicy *policy, dispatch_queue_t callbacks,
    QONRemoteConfigV2FetchPolicyPersistenceFailureObserver observer) {
  return [[QONRemoteConfigV2FetchCoordinator alloc] initWithCore:core transport:transport
      policyStore:store clock:clock random:random scheduler:scheduler policy:policy
      callbackExecutor:callbacks policyPersistenceFailureObserver:observer];
}

static void Drain(dispatch_queue_t callbacks) { dispatch_sync(callbacks, ^{}); }

static void TestCoalescingAndCallbackIsolation(void) {
  HarnessCore *core = [HarnessCore new]; core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  HarnessTransport *transport = [HarnessTransport new]; HarnessStore *store = [HarnessStore new];
  HarnessClock *clock = [HarnessClock new]; HarnessRandom *random = [HarnessRandom new];
  HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.coalesce", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block NSUInteger delivered = 0;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(__unused id result) {
    delivered += 1; @throw [NSException exceptionWithName:@"consumer" reason:nil userInfo:nil];
  }];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild completion:^(__unused id result) {
    delivered += 1;
  }];
  QON_CHECK(transport.requests.count == 1, "coalesced callers must share one HTTP request");
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"etag" projectID:42]];
  Drain(callbacks);
  QON_CHECK(delivered == 2, "throwing callback must not starve the next waiter");
  QON_CHECK(core.admissions == 1 && core.admittedBodies == 1, "coalesced operation admits once");
}

// A success that states no project id has no envelope boundary to be checked
// against, so the coordinator must never hand it to the core.
static void TestASuccessWithoutAProjectIDIsNeverAdmitted(void) {
  HarnessCore *core = [HarnessCore new];
  core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  HarnessTransport *transport = [HarnessTransport new]; HarnessStore *store = [HarnessStore new];
  HarnessClock *clock = [HarnessClock new]; HarnessRandom *random = [HarnessRandom new];
  HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.noproject",
                                                     DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];

  __block QONRemoteConfigV2FetchResult *result = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
                         completion:^(QONRemoteConfigV2FetchResult *value) { result = value; }];
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"etag" projectID:0]];
  Drain(callbacks);
  QON_CHECK(core.admittedBodies == 0, "a success without a project id must not reach the core");
  QON_CHECK(result.transitionStatus == QONRemoteConfigV2TransitionStatusRejected,
            "it must be reported as rejected, not as an admitted release");

  // The same bytes with a stated id are admitted, so the refusal is about the
  // missing boundary and nothing else.
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild
                         completion:^(__unused id value) {}];
  [transport complete:1 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"etag" projectID:42]];
  Drain(callbacks);
  QON_CHECK(core.admittedBodies == 1 && core.lastAdmittedProjectID == 42,
            "a stated project id must reach the core verbatim");
}

static void TestBackoffScopeAndForce(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new]; clock.now = 1000;
  HarnessRandom *random = [HarnessRandom new]; random.value = 0.25; HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.backoff", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *failure = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id result) { failure = result; }];
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse failureWithStatusCode:@503
      retryAfterMilliseconds:@5000]];
  Drain(callbacks);
  QONRemoteConfigV2FetchPolicyState *saved = store.states[@"project/production"];
  QON_CHECK(failure.kind == QONRemoteConfigV2FetchResultKindFailed, "retryable HTTP completes the waiter");
  QON_CHECK(saved.nextAllowedFetchAtMilliseconds == 6000, "Retry-After must override jitter");
  [coordinator transitionToBinding:Binding(@"b")];
  __block QONRemoteConfigV2FetchResult *gated = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonIdentify completion:^(id result) { gated = result; }];
  Drain(callbacks);
  QON_CHECK(gated.kind == QONRemoteConfigV2FetchResultKindBackoff,
      "identity and lifecycle force must not bypass project-environment backoff");
  QON_CHECK(transport.requests.count == 1, "backoff must suppress transport");
}

static void TestMinimumIntervalForceOnly(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new]; clock.now = 1500;
  HarnessRandom *random = [HarnessRandom new]; HarnessScheduler *scheduler = [HarnessScheduler new];
  store.states[@"project/production"] = [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:1000 consecutiveRetryableFailures:0
      nextAllowedFetchAtMilliseconds:0];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.minimum", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(1000, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *gated = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id result) { gated = result; }];
  Drain(callbacks);
  QON_CHECK(gated.kind == QONRemoteConfigV2FetchResultKindMinimumInterval,
      "ordinary fetch must honor minimum interval");
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild completion:^(__unused id result) {}];
  QON_CHECK(transport.requests.count == 1, "lifecycle force may bypass only minimum interval");
}

static void TestTimeoutAndZombieFence(void) {
  HarnessCore *core = [HarnessCore new]; core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  core.snapshot = (id)[NSObject new];
  HarnessTransport *transport = [HarnessTransport new]; HarnessStore *store = [HarnessStore new];
  HarnessClock *clock = [HarnessClock new]; HarnessRandom *random = [HarnessRandom new];
  HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.timeout", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, @100), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block NSMutableArray *results = [NSMutableArray new];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id result) { [results addObject:result]; }];
  [scheduler fire:0]; Drain(callbacks);
  QONRemoteConfigV2FetchResult *timeout = results.firstObject;
  QON_CHECK(timeout.kind == QONRemoteConfigV2FetchResultKindTimedOut && timeout.snapshot == core.snapshot,
      "timeout must return best current Active-to-bundle snapshot");
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id result) { [results addObject:result]; }];
  QON_CHECK(transport.requests.count == 2 && core.admissions == 2,
      "new fetch after all waiters timeout must supersede zombie without cancelling HTTP");
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"old" projectID:42]];
  [transport complete:1 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"new" projectID:42]];
  Drain(callbacks);
  QON_CHECK(results.count == 2 && core.admittedBodies == 1,
      "late zombie response must be fenced while new response persists Candidate");
}

static void TestConditional304Retry(void) {
  HarnessCore *core = [HarnessCore new];
  core.validator = [[QONRemoteConfigV2ConditionalRequestValidator alloc]
      initWithStrongETag:@"\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
      bodyDigest:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      headAdmissionOrdinal:1];
  HarnessTransport *transport = [HarnessTransport new]; HarnessStore *store = [HarnessStore new];
  HarnessClock *clock = [HarnessClock new]; HarnessRandom *random = [HarnessRandom new];
  HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.etag", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *result = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id value) { result = value; }];
  QON_CHECK([transport.requests[0] ifNoneMatch] != nil, "exact current head must send its ETag");
  core.validator = nil;
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse notModifiedWithStrongETag:nil]];
  QON_CHECK(transport.requests.count == 2 && [transport.requests[1] ifNoneMatch] == nil,
      "stale 304 must retry once without ETag");
  [transport complete:1 response:[QONRemoteConfigV2FetchResponse notModifiedWithStrongETag:nil]];
  Drain(callbacks);
  QON_CHECK(result.kind == QONRemoteConfigV2FetchResultKindInvalidNotModified && transport.requests.count == 2,
      "second invalid 304 must terminate without a retry loop");
}

static void TestMatching304IsAccepted(void) {
  HarnessCore *core = [HarnessCore new];
  core.validator = [[QONRemoteConfigV2ConditionalRequestValidator alloc]
      initWithStrongETag:@"\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
      bodyDigest:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      headAdmissionOrdinal:1];
  HarnessTransport *transport = [HarnessTransport new]; HarnessStore *store = [HarnessStore new];
  HarnessClock *clock = [HarnessClock new]; clock.now = 777;
  HarnessRandom *random = [HarnessRandom new]; HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.etag.match", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *result = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(id value) { result = value; }];
  NSString *etag = core.validator.strongETag;
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse notModifiedWithStrongETag:etag]];
  Drain(callbacks);
  QONRemoteConfigV2FetchPolicyState *saved = store.states[@"project/production"];
  QON_CHECK(result.kind == QONRemoteConfigV2FetchResultKindNotModified && transport.requests.count == 1,
      "304 may be accepted only for the exact current canonical head validator");
  QON_CHECK(saved.lastSuccessfulFetchAtMilliseconds == 777,
      "accepted 304 must refresh the successful-fetch policy timestamp");
}

static void TestCappedExponentialFullJitter(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new]; clock.now = 100;
  HarnessRandom *random = [HarnessRandom new]; random.value = 0.25;
  HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.jitter", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:0 timeoutMilliseconds:nil
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:4000];
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, policy, callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  int64_t expectedDeadlines[] = {350, 850, 1850, 2850};
  for (NSUInteger index = 0; index < 4; index++) {
    [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
        completion:^(__unused id value) {}];
    [transport complete:index response:[QONRemoteConfigV2FetchResponse
        failureWithStatusCode:@503 retryAfterMilliseconds:nil]];
    Drain(callbacks);
    QONRemoteConfigV2FetchPolicyState *saved = store.states[@"project/production"];
    QON_CHECK(saved.consecutiveRetryableFailures == (NSInteger)index + 1,
        "retryable failures must increment the durable counter");
    QON_CHECK(saved.nextAllowedFetchAtMilliseconds == expectedDeadlines[index],
        "backoff must use capped exponential full jitter");
    clock.now = expectedDeadlines[index];
  }
}

static void TestTransportAndSchedulerExceptionsCannotHangWaiters(void) {
  HarnessCore *core = [HarnessCore new]; core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  HarnessTransport *transport = [HarnessTransport new]; transport.throws = YES;
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new];
  HarnessRandom *random = [HarnessRandom new]; HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.exceptions", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, @100), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *transportResult = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(id value) { transportResult = value; }];
  Drain(callbacks);
  QON_CHECK(transportResult.kind == QONRemoteConfigV2FetchResultKindFailed,
      "transport exception must terminate every waiter exactly once");

  HarnessCore *secondCore = [HarnessCore new]; secondCore.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  HarnessTransport *secondTransport = [HarnessTransport new];
  HarnessScheduler *throwingScheduler = [HarnessScheduler new]; throwingScheduler.throws = YES;
  QONRemoteConfigV2FetchCoordinator *secondCoordinator = Coordinator(secondCore, secondTransport,
      [HarnessStore new], clock, random, throwingScheduler, Policy(0, @100), callbacks, nil);
  [secondCoordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *schedulerResult = nil;
  [secondCoordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(id value) { schedulerResult = value; }];
  [secondTransport complete:0 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"etag" projectID:42]];
  Drain(callbacks);
  QON_CHECK(schedulerResult.kind == QONRemoteConfigV2FetchResultKindFetched,
      "scheduler exception must not block transport completion");
}

static void TestNilStatusAndTransportExceptionPersistBackoffAcrossRestart(void) {
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new]; clock.now = 1000;
  HarnessRandom *random = [HarnessRandom new]; random.value = 0.5;
  HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.network-backoff", DISPATCH_QUEUE_SERIAL);
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(__unused id value) {}];
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse
      failureWithStatusCode:nil retryAfterMilliseconds:nil]];
  Drain(callbacks);
  QONRemoteConfigV2FetchPolicyState *afterNilStatus = store.states[@"project/production"];
  QON_CHECK(afterNilStatus.consecutiveRetryableFailures == 1 &&
      afterNilStatus.nextAllowedFetchAtMilliseconds == 1500,
      "nil-status network failure must persist full-jitter backoff");

  HarnessCore *restartCore = [HarnessCore new]; HarnessTransport *restartTransport = [HarnessTransport new];
  QONRemoteConfigV2FetchCoordinator *restart = Coordinator(restartCore, restartTransport, store, clock,
      random, [HarnessScheduler new], Policy(0, nil), callbacks, nil);
  [restart transitionToBinding:Binding(@"b")];
  __block QONRemoteConfigV2FetchResult *restartResult = nil;
  [restart fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild
      completion:^(id value) { restartResult = value; }];
  Drain(callbacks);
  QON_CHECK(restartResult.kind == QONRemoteConfigV2FetchResultKindBackoff &&
      restartTransport.requests.count == 0,
      "persisted nil-status backoff must survive restart and lifecycle force");

  clock.now = afterNilStatus.nextAllowedFetchAtMilliseconds;
  HarnessTransport *throwingTransport = [HarnessTransport new]; throwingTransport.throws = YES;
  QONRemoteConfigV2FetchCoordinator *afterDeadline = Coordinator([HarnessCore new], throwingTransport,
      store, clock, random, [HarnessScheduler new], Policy(0, nil), callbacks, nil);
  [afterDeadline transitionToBinding:Binding(@"c")];
  [afterDeadline fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(__unused id value) {}];
  Drain(callbacks);
  QONRemoteConfigV2FetchPolicyState *afterException = store.states[@"project/production"];
  QON_CHECK(afterException.consecutiveRetryableFailures == 2 &&
      afterException.nextAllowedFetchAtMilliseconds == 2500,
      "transport exception must persist the next capped exponential backoff deadline");
}

static void TestPersistenceFailureIsObservableAndConservative(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; store.saveSucceeds = NO;
  HarnessClock *clock = [HarnessClock new]; clock.now = 1000; HarnessRandom *random = [HarnessRandom new];
  random.value = 0.5; HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.persistence", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger observedFailures = 0;
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks,
      ^(__unused QONRemoteConfigV2FetchPolicyScope *scope,
        __unused QONRemoteConfigV2FetchPolicyFailureReason reason) { observedFailures += 1; });
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *first = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id result) { first = result; }];
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse failureWithStatusCode:@503
      retryAfterMilliseconds:@5000]];
  Drain(callbacks);
  QON_CHECK(first.kind == QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed && observedFailures == 1,
      "policy save failure must be explicit and observable");
  __block QONRemoteConfigV2FetchResult *second = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonLogout completion:^(id result) { second = result; }];
  Drain(callbacks);
  QON_CHECK(second.kind == QONRemoteConfigV2FetchResultKindBackoff && transport.requests.count == 1,
      "failed durable save must retain conservative backoff in-process");
}

static void TestTransitionClaimsOldWaitersOnce(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new];
  HarnessRandom *random = [HarnessRandom new]; HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.scope", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  __block NSMutableArray *results = [NSMutableArray new];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone completion:^(id result) { [results addObject:result]; }];
  [coordinator transitionToBinding:Binding(@"b")]; Drain(callbacks);
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"late" projectID:42]];
  Drain(callbacks);
  QONRemoteConfigV2FetchResult *result = results.firstObject;
  QON_CHECK(results.count == 1 && result.kind == QONRemoteConfigV2FetchResultKindSuperseded,
      "identity transition must complete old waiter once and fence late response");
}

static void TestPersistentPolicyStoreScopeAndReadback(void) {
  HarnessLocalStorage *storage = [HarnessLocalStorage new];
  QONRemoteConfigV2FetchPolicyStore *store = [[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage];
  QONRemoteConfigV2FetchPolicyScope *production = [[QONRemoteConfigV2FetchPolicyScope alloc]
      initWithProjectKey:@"project" environment:@"production"];
  QONRemoteConfigV2FetchPolicyScope *sandbox = [[QONRemoteConfigV2FetchPolicyScope alloc]
      initWithProjectKey:@"project" environment:@"sandbox"];
  QONRemoteConfigV2FetchPolicyState *state = [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:100 consecutiveRetryableFailures:3
      nextAllowedFetchAtMilliseconds:900];
  QON_CHECK([store saveState:state forScope:production], "policy state must persist durably");
  QONRemoteConfigV2FetchPolicyLoadResult *loadedResult = [[[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage] loadResultForScope:production];
  QONRemoteConfigV2FetchPolicyState *loaded = loadedResult.state;
  QON_CHECK(loadedResult.status == QONRemoteConfigV2FetchPolicyLoadStatusFound,
      "valid durable policy state must be distinguished as Found");
  QON_CHECK(loaded.consecutiveRetryableFailures == 3 && loaded.nextAllowedFetchAtMilliseconds == 900,
      "policy state must survive restart");
  QON_CHECK([store loadResultForScope:sandbox].status == QONRemoteConfigV2FetchPolicyLoadStatusMissing,
      "policy state key must bind exact project and environment");
  NSString *storageKey = storage.objects.allKeys.firstObject;
  QON_CHECK(storageKey.length > 0 && [storageKey rangeOfString:@"project"].location == NSNotFound,
      "durable key must be a bounded digest, not raw scope data");
  storage.ignoreWrites = YES;
  QONRemoteConfigV2FetchPolicyState *replacement = [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:200 consecutiveRetryableFailures:4
      nextAllowedFetchAtMilliseconds:1000];
  QON_CHECK(![store saveState:replacement forScope:production],
      "silent storage write loss must fail exact read-back verification");
  QON_CHECK([store loadResultForScope:production].state.nextAllowedFetchAtMilliseconds == 900,
      "failed write must preserve prior durable policy state");
}

static void TestPersistentPolicyStoreDistinguishesMissingFailedAndCorrupt(void) {
  HarnessLocalStorage *storage = [HarnessLocalStorage new];
  QONRemoteConfigV2FetchPolicyScope *scope = [[QONRemoteConfigV2FetchPolicyScope alloc]
      initWithProjectKey:@"project" environment:@"production"];
  QONRemoteConfigV2FetchPolicyStore *store = [[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage];
  QON_CHECK([store loadResultForScope:scope].status == QONRemoteConfigV2FetchPolicyLoadStatusMissing,
      "absent durable policy must be distinguished as Missing");
  QONRemoteConfigV2FetchPolicyState *state = [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:100 consecutiveRetryableFailures:2
      nextAllowedFetchAtMilliseconds:900];
  QON_CHECK([store saveState:state forScope:scope], "valid policy must persist before corruption test");
  NSString *key = storage.objects.allKeys.firstObject;
  NSDictionary *valid = storage.objects[key];

  NSMutableDictionary *badShape = [valid mutableCopy];
  [badShape removeObjectForKey:@"next_allowed_fetch_at_ms"];
  storage.objects[key] = badShape;
  QONRemoteConfigV2FetchPolicyLoadResult *shapeResult = [[[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage] loadResultForScope:scope];
  QON_CHECK(shapeResult.status == QONRemoteConfigV2FetchPolicyLoadStatusCorrupt &&
      [storage.objects[key] isEqual:badShape],
      "shape corruption must remain quarantined and observable, not deleted as Missing");

  NSMutableDictionary *badDigest = [valid mutableCopy];
  badDigest[@"integrity_digest"] = [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
  storage.objects[key] = badDigest;
  QONRemoteConfigV2FetchPolicyLoadResult *digestResult = [[[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage] loadResultForScope:scope];
  QON_CHECK(digestResult.status == QONRemoteConfigV2FetchPolicyLoadStatusCorrupt &&
      [storage.objects[key] isEqual:badDigest],
      "integrity mismatch must be Corrupt and must not be silently removed");

  storage.throwsOnRead = YES;
  QONRemoteConfigV2FetchPolicyLoadResult *failed = [[[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage] loadResultForScope:scope];
  QON_CHECK(failed.status == QONRemoteConfigV2FetchPolicyLoadStatusFailed,
      "storage read exception must be distinguished as Failed");
}

static void TestPolicyLoadFailureFailsClosedBeforeNetwork(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; store.throwsOnLoad = YES;
  HarnessClock *clock = [HarnessClock new]; clock.now = 1000;
  HarnessRandom *random = [HarnessRandom new]; HarnessScheduler *scheduler = [HarnessScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.load-failure", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger observations = 0;
  __block QONRemoteConfigV2FetchPolicyFailureReason observedReason =
      QONRemoteConfigV2FetchPolicyFailureReasonSave;
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      random, scheduler, Policy(0, nil), callbacks,
      ^(__unused QONRemoteConfigV2FetchPolicyScope *scope,
        QONRemoteConfigV2FetchPolicyFailureReason reason) {
    observations += 1;
    observedReason = reason;
  });
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *first = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild
      completion:^(id value) { first = value; }];
  Drain(callbacks);
  QON_CHECK(first.kind == QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed &&
      first.policyFailureReason == QONRemoteConfigV2FetchPolicyFailureReasonLoadFailed &&
      first.nextAllowedAtMilliseconds == 2000,
      "load exception must emit an explicit bounded failure result before network");
  QON_CHECK(observations == 1 && observedReason == QONRemoteConfigV2FetchPolicyFailureReasonLoadFailed &&
      transport.requests.count == 0,
      "load exception telemetry must be bounded and network must fail closed");

  __block QONRemoteConfigV2FetchResult *second = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonLogout
      completion:^(id value) { second = value; }];
  Drain(callbacks);
  QON_CHECK(second.kind == QONRemoteConfigV2FetchResultKindBackoff && observations == 1 &&
      transport.requests.count == 0,
      "subsequent callers must observe conservative in-process backoff without telemetry spam");

  HarnessTransport *restartTransport = [HarnessTransport new];
  QONRemoteConfigV2FetchCoordinator *restart = Coordinator([HarnessCore new], restartTransport, store,
      clock, random, [HarnessScheduler new], Policy(0, nil), callbacks, nil);
  [restart transitionToBinding:Binding(@"b")];
  __block QONRemoteConfigV2FetchResult *restartResult = nil;
  [restart fetchWithForceReason:QONRemoteConfigV2FetchForceReasonIdentify
      completion:^(id value) { restartResult = value; }];
  Drain(callbacks);
  QON_CHECK(restartResult.kind == QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed &&
      restartTransport.requests.count == 0,
      "read failure must fail closed again after coordinator restart");
}

static void TestCorruptPolicyFailsClosedWithoutSilentDeletion(void) {
  HarnessLocalStorage *storage = [HarnessLocalStorage new];
  QONRemoteConfigV2FetchPolicyStore *store = [[QONRemoteConfigV2FetchPolicyStore alloc]
      initWithLocalStorage:storage];
  QONRemoteConfigV2FetchPolicyScope *scope = [[QONRemoteConfigV2FetchPolicyScope alloc]
      initWithProjectKey:@"project" environment:@"production"];
  QONRemoteConfigV2FetchPolicyState *state = [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:100 consecutiveRetryableFailures:1
      nextAllowedFetchAtMilliseconds:900];
  QON_CHECK([store saveState:state forScope:scope], "valid policy must persist before fail-closed test");
  NSString *key = storage.objects.allKeys.firstObject;
  NSMutableDictionary *corrupt = [storage.objects[key] mutableCopy];
  corrupt[@"integrity_digest"] = [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0];
  storage.objects[key] = corrupt;

  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessClock *clock = [HarnessClock new]; clock.now = 1000;
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.corrupt", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger observations = 0;
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      [HarnessRandom new], [HarnessScheduler new], Policy(0, nil), callbacks,
      ^(__unused QONRemoteConfigV2FetchPolicyScope *observedScope,
        QONRemoteConfigV2FetchPolicyFailureReason reason) {
    if (reason == QONRemoteConfigV2FetchPolicyFailureReasonLoadCorrupt) observations += 1;
  });
  [coordinator transitionToBinding:Binding(@"a")];
  __block QONRemoteConfigV2FetchResult *result = nil;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild
      completion:^(id value) { result = value; }];
  Drain(callbacks);
  QON_CHECK(result.kind == QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed &&
      result.policyFailureReason == QONRemoteConfigV2FetchPolicyFailureReasonLoadCorrupt &&
      result.nextAllowedAtMilliseconds == 2000 && transport.requests.count == 0,
      "corrupt durable guard state must emit explicit result and initial bounded delay before network");
  QON_CHECK(observations == 1 && [storage.objects[key] isEqual:corrupt],
      "corrupt policy telemetry must be bounded and the evidence must not be silently deleted");
}

static void TestOnlyExplicitNon429ClientErrorsAreNonRetryable(void) {
  HarnessCore *core = [HarnessCore new]; HarnessTransport *transport = [HarnessTransport new];
  HarnessStore *store = [HarnessStore new]; HarnessClock *clock = [HarnessClock new]; clock.now = 1000;
  dispatch_queue_t callbacks = dispatch_queue_create("fetch.harness.http-4xx", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchCoordinator *coordinator = Coordinator(core, transport, store, clock,
      [HarnessRandom new], [HarnessScheduler new], Policy(0, nil), callbacks, nil);
  [coordinator transitionToBinding:Binding(@"a")];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(__unused id value) {}];
  [transport complete:0 response:[QONRemoteConfigV2FetchResponse
      failureWithStatusCode:@404 retryAfterMilliseconds:nil]];
  Drain(callbacks);
  QON_CHECK(store.states[@"project/production"] == nil,
      "explicit non-429 4xx must not create retry backoff");

  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(__unused id value) {}];
  [transport complete:1 response:[QONRemoteConfigV2FetchResponse
      failureWithStatusCode:@429 retryAfterMilliseconds:@1000]];
  Drain(callbacks);
  QONRemoteConfigV2FetchPolicyState *afterRateLimit = store.states[@"project/production"];
  QON_CHECK(afterRateLimit.nextAllowedFetchAtMilliseconds == 2000,
      "429 must remain retryable and persist Retry-After backoff");
}

int main(void) {
  @autoreleasepool {
    TestCoalescingAndCallbackIsolation();
    TestASuccessWithoutAProjectIDIsNeverAdmitted();
    TestBackoffScopeAndForce();
    TestMinimumIntervalForceOnly();
    TestTimeoutAndZombieFence();
    TestConditional304Retry();
    TestMatching304IsAccepted();
    TestCappedExponentialFullJitter();
    TestTransportAndSchedulerExceptionsCannotHangWaiters();
    TestNilStatusAndTransportExceptionPersistBackoffAcrossRestart();
    TestPersistenceFailureIsObservableAndConservative();
    TestTransitionClaimsOldWaitersOnce();
    TestPersistentPolicyStoreScopeAndReadback();
    TestPersistentPolicyStoreDistinguishesMissingFailedAndCorrupt();
    TestPolicyLoadFailureFailsClosedBeforeNetwork();
    TestCorruptPolicyFailsClosedWithoutSilentDeletion();
    TestOnlyExplicitNon429ClientErrorsAreNonRetryable();
  }
  fprintf(stdout, "QONRemoteConfigV2FetchCoordinatorHarness: %lu/%lu passed\n",
          (unsigned long)(checks - failures), (unsigned long)checks);
  return failures == 0 ? 0 : 1;
}
