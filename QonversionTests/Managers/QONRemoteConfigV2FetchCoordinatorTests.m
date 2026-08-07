#import <XCTest/XCTest.h>

#import "QONRemoteConfigV2FetchCoordinator.h"

@interface QONRemoteConfigV2FetchTestTask : NSObject <QONRemoteConfigV2FetchScheduledTask>
@property (nonatomic, copy) dispatch_block_t action;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation QONRemoteConfigV2FetchTestTask
- (void)cancel { self.cancelled = YES; }
@end

@interface QONRemoteConfigV2FetchTestScheduler : NSObject <QONRemoteConfigV2FetchScheduler>
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2FetchTestTask *> *tasks;
- (void)fireTaskAtIndex:(NSUInteger)index;
@end

@implementation QONRemoteConfigV2FetchTestScheduler
- (instancetype)init { self = [super init]; if (self) _tasks = [NSMutableArray new]; return self; }
- (id<QONRemoteConfigV2FetchScheduledTask>)scheduleAfterMilliseconds:(int64_t)delay
                                                              action:(dispatch_block_t)action {
  QONRemoteConfigV2FetchTestTask *task = [QONRemoteConfigV2FetchTestTask new];
  task.action = action;
  [self.tasks addObject:task];
  return task;
}
- (void)fireTaskAtIndex:(NSUInteger)index {
  QONRemoteConfigV2FetchTestTask *task = self.tasks[index];
  if (!task.cancelled) task.action();
}
@end

@interface QONRemoteConfigV2FetchTestClock : NSObject <QONRemoteConfigV2FetchClock>
@property (nonatomic, assign) int64_t now;
@end
@implementation QONRemoteConfigV2FetchTestClock
- (int64_t)nowMilliseconds { return self.now; }
@end

@interface QONRemoteConfigV2FetchTestRandom : NSObject <QONRemoteConfigV2FetchRandom>
@property (nonatomic, assign) double value;
@end
@implementation QONRemoteConfigV2FetchTestRandom
- (double)nextUnitInterval { return self.value; }
@end

@interface QONRemoteConfigV2FetchTestPolicyStore : NSObject <QONRemoteConfigV2FetchPolicyStoring>
@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigV2FetchPolicyState *> *states;
@property (nonatomic, assign) BOOL saveSucceeds;
@end

@implementation QONRemoteConfigV2FetchTestPolicyStore
- (instancetype)init { self = [super init]; if (self) { _states = [NSMutableDictionary new]; _saveSucceeds = YES; } return self; }
- (NSString *)key:(QONRemoteConfigV2FetchPolicyScope *)scope {
  return [NSString stringWithFormat:@"%@\n%@", scope.projectKey, scope.environment];
}
- (QONRemoteConfigV2FetchPolicyLoadResult *)loadResultForScope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  QONRemoteConfigV2FetchPolicyState *state = self.states[[self key:scope]];
  return [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
      initWithStatus:state ? QONRemoteConfigV2FetchPolicyLoadStatusFound
                         : QONRemoteConfigV2FetchPolicyLoadStatusMissing
               state:state];
}
- (BOOL)saveState:(QONRemoteConfigV2FetchPolicyState *)state
          forScope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  if (!self.saveSucceeds) return NO;
  self.states[[self key:scope]] = state;
  return YES;
}
@end

@interface QONRemoteConfigV2FetchTestTransport : NSObject <QONRemoteConfigV2FetchTransport>
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2FetchRequest *> *requests;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2FetchTransportCompletion> *completions;
@end

@implementation QONRemoteConfigV2FetchTestTransport
- (instancetype)init { self = [super init]; if (self) { _requests = [NSMutableArray new]; _completions = [NSMutableArray new]; } return self; }
- (void)fetchRequest:(QONRemoteConfigV2FetchRequest *)request
          completion:(QONRemoteConfigV2FetchTransportCompletion)completion {
  [self.requests addObject:request];
  [self.completions addObject:[completion copy]];
}
@end

@interface QONRemoteConfigV2FetchTestCore : NSObject <QONRemoteConfigV2FetchCore>
@property (nonatomic, strong) QONRemoteConfigV2Scope *currentScope;
@property (nonatomic, strong) QONRemoteConfigV2ConditionalRequestValidator *validator;
@property (nonatomic, strong) QONRemoteConfigSnapshot *snapshot;
@property (nonatomic, assign) NSUInteger admissions;
@property (nonatomic, assign) NSUInteger admittedBodies;
@property (nonatomic, assign) QONRemoteConfigV2TransitionStatus transitionStatus;
@end

@implementation QONRemoteConfigV2FetchTestCore
- (void)setScope:(QONRemoteConfigV2Scope *)scope { self.currentScope = scope; }
- (QONRemoteConfigSnapshot *)unguardedSnapshot { return self.snapshot; }
- (QONRemoteConfigV2AdmissionToken *)beginAdmissionForScope:(QONRemoteConfigV2Scope *)scope
                                                expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation {
  self.admissions += 1;
  return (id)[NSObject new];
}
- (QONRemoteConfigV2TransitionStatus)admitBody:(NSData *)body
                                   strongETag:(NSString *)strongETag
                               admissionToken:(QONRemoteConfigV2AdmissionToken *)admissionToken {
  self.admittedBodies += 1;
  return self.transitionStatus;
}
- (QONRemoteConfigV2ConditionalRequestValidator *)conditionalRequestValidator { return self.validator; }
- (BOOL)isConditionalRequestValidatorCurrent:(QONRemoteConfigV2ConditionalRequestValidator *)validator {
  return [self.validator isEqual:validator];
}
@end

@interface QONRemoteConfigV2FetchCoordinatorTests : XCTestCase
@end

@implementation QONRemoteConfigV2FetchCoordinatorTests

- (QONRemoteConfigV2FetchBinding *)bindingForUser:(NSString *)user {
  QONRemoteConfigV2Scope *scope = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:user];
  QONRemoteConfigV2EnvelopeExpectation *expectation = [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:42 environmentUID:@"production"
      contextFingerprint:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]];
  return [[QONRemoteConfigV2FetchBinding alloc] initWithScope:scope expectation:expectation];
}

- (QONRemoteConfigV2FetchCoordinator *)coordinatorWithCore:(QONRemoteConfigV2FetchTestCore *)core
                                                 transport:(QONRemoteConfigV2FetchTestTransport *)transport
                                                     store:(QONRemoteConfigV2FetchTestPolicyStore *)store
                                                     clock:(QONRemoteConfigV2FetchTestClock *)clock
                                                    policy:(QONRemoteConfigV2FetchPolicy *)policy {
  dispatch_queue_t callbacks = dispatch_queue_create("io.qonversion.fetch-policy-tests", DISPATCH_QUEUE_SERIAL);
  return [[QONRemoteConfigV2FetchCoordinator alloc] initWithCore:core transport:transport
      policyStore:store clock:clock random:[QONRemoteConfigV2FetchTestRandom new]
      scheduler:[QONRemoteConfigV2FetchTestScheduler new] policy:policy
      callbackExecutor:callbacks policyPersistenceFailureObserver:nil];
}

- (void)testConcurrentFetchesCoalesceIntoOneTransportRequest {
  QONRemoteConfigV2FetchTestCore *core = [QONRemoteConfigV2FetchTestCore new];
  core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  QONRemoteConfigV2FetchTestTransport *transport = [QONRemoteConfigV2FetchTestTransport new];
  QONRemoteConfigV2FetchTestPolicyStore *store = [QONRemoteConfigV2FetchTestPolicyStore new];
  QONRemoteConfigV2FetchTestClock *clock = [QONRemoteConfigV2FetchTestClock new];
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:0 timeoutMilliseconds:nil
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000];
  QONRemoteConfigV2FetchCoordinator *coordinator = [self coordinatorWithCore:core
      transport:transport store:store clock:clock policy:policy];
  [coordinator transitionToBinding:[self bindingForUser:@"user"]];
  XCTestExpectation *both = [self expectationWithDescription:@"both waiters"];
  both.expectedFulfillmentCount = 2;

  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
                         completion:^(__unused QONRemoteConfigV2FetchResult *result) { [both fulfill]; }];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonBuild
                         completion:^(__unused QONRemoteConfigV2FetchResult *result) { [both fulfill]; }];
  XCTAssertEqual(transport.requests.count, 1u);
  transport.completions.firstObject([QONRemoteConfigV2FetchResponse
      successWithBody:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] strongETag:@"etag"]);
  [self waitForExpectations:@[both] timeout:2];
  XCTAssertEqual(core.admissions, 1u);
}

- (void)testRetryAfterBackoffPersistsAcrossIdentityAndLifecycleForceCannotBypassIt {
  QONRemoteConfigV2FetchTestCore *core = [QONRemoteConfigV2FetchTestCore new];
  QONRemoteConfigV2FetchTestTransport *transport = [QONRemoteConfigV2FetchTestTransport new];
  QONRemoteConfigV2FetchTestPolicyStore *store = [QONRemoteConfigV2FetchTestPolicyStore new];
  QONRemoteConfigV2FetchTestClock *clock = [QONRemoteConfigV2FetchTestClock new];
  clock.now = 1000;
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:0 timeoutMilliseconds:nil
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000];
  QONRemoteConfigV2FetchCoordinator *coordinator = [self coordinatorWithCore:core
      transport:transport store:store clock:clock policy:policy];
  [coordinator transitionToBinding:[self bindingForUser:@"user-a"]];
  XCTestExpectation *failed = [self expectationWithDescription:@"failure"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(__unused QONRemoteConfigV2FetchResult *result) { [failed fulfill]; }];
  transport.completions[0]([QONRemoteConfigV2FetchResponse failureWithStatusCode:@503
      retryAfterMilliseconds:@5000]);
  [self waitForExpectations:@[failed] timeout:2];
  QONRemoteConfigV2FetchPolicyState *saved = store.states[@"project\nproduction"];
  XCTAssertEqual(saved.nextAllowedFetchAtMilliseconds, 6000);

  [coordinator transitionToBinding:[self bindingForUser:@"user-b"]];
  for (NSNumber *force in @[@(QONRemoteConfigV2FetchForceReasonBuild),
                            @(QONRemoteConfigV2FetchForceReasonIdentify),
                            @(QONRemoteConfigV2FetchForceReasonLogout)]) {
    XCTestExpectation *gated = [self expectationWithDescription:@"gated"];
    [coordinator fetchWithForceReason:force.integerValue completion:^(QONRemoteConfigV2FetchResult *result) {
      XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindBackoff);
      [gated fulfill];
    }];
    [self waitForExpectations:@[gated] timeout:2];
  }
  XCTAssertEqual(transport.requests.count, 1u);
}

- (void)testTimeoutReturnsSnapshotWithoutCancellingHTTPAndLateResponsePersistsCandidate {
  QONRemoteConfigV2FetchTestCore *core = [QONRemoteConfigV2FetchTestCore new];
  core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  core.snapshot = (id)[NSObject new];
  QONRemoteConfigV2FetchTestTransport *transport = [QONRemoteConfigV2FetchTestTransport new];
  QONRemoteConfigV2FetchTestPolicyStore *store = [QONRemoteConfigV2FetchTestPolicyStore new];
  QONRemoteConfigV2FetchTestClock *clock = [QONRemoteConfigV2FetchTestClock new];
  QONRemoteConfigV2FetchTestRandom *random = [QONRemoteConfigV2FetchTestRandom new];
  QONRemoteConfigV2FetchTestScheduler *scheduler = [QONRemoteConfigV2FetchTestScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("io.qonversion.fetch-timeout-tests", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:0 timeoutMilliseconds:@100
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000];
  QONRemoteConfigV2FetchCoordinator *coordinator = [[QONRemoteConfigV2FetchCoordinator alloc]
      initWithCore:core transport:transport policyStore:store clock:clock random:random
      scheduler:scheduler policy:policy callbackExecutor:callbacks
      policyPersistenceFailureObserver:nil];
  [coordinator transitionToBinding:[self bindingForUser:@"user"]];
  XCTestExpectation *timedOut = [self expectationWithDescription:@"timed out"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(QONRemoteConfigV2FetchResult *result) {
    XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindTimedOut);
    XCTAssertEqual(result.snapshot, core.snapshot);
    [timedOut fulfill];
  }];
  [scheduler fireTaskAtIndex:0];
  [self waitForExpectations:@[timedOut] timeout:2];
  transport.completions[0]([QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"etag"]);
  dispatch_sync(callbacks, ^{});
  XCTAssertEqual(core.admittedBodies, 1u);
  XCTAssertNotNil(store.states[@"project\nproduction"]);
}

- (void)testNewFetchAfterAllWaitersTimeoutSupersedesZombieWithoutCancellingOldHTTP {
  QONRemoteConfigV2FetchTestCore *core = [QONRemoteConfigV2FetchTestCore new];
  core.transitionStatus = QONRemoteConfigV2TransitionStatusAccepted;
  QONRemoteConfigV2FetchTestTransport *transport = [QONRemoteConfigV2FetchTestTransport new];
  QONRemoteConfigV2FetchTestPolicyStore *store = [QONRemoteConfigV2FetchTestPolicyStore new];
  QONRemoteConfigV2FetchTestClock *clock = [QONRemoteConfigV2FetchTestClock new];
  QONRemoteConfigV2FetchTestScheduler *scheduler = [QONRemoteConfigV2FetchTestScheduler new];
  dispatch_queue_t callbacks = dispatch_queue_create("io.qonversion.fetch-zombie-tests", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:0 timeoutMilliseconds:@100
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000];
  QONRemoteConfigV2FetchCoordinator *coordinator = [[QONRemoteConfigV2FetchCoordinator alloc]
      initWithCore:core transport:transport policyStore:store clock:clock
      random:[QONRemoteConfigV2FetchTestRandom new] scheduler:scheduler policy:policy
      callbackExecutor:callbacks policyPersistenceFailureObserver:nil];
  [coordinator transitionToBinding:[self bindingForUser:@"user"]];

  XCTestExpectation *timedOut = [self expectationWithDescription:@"old waiter times out"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(QONRemoteConfigV2FetchResult *result) {
    XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindTimedOut);
    [timedOut fulfill];
  }];
  [scheduler fireTaskAtIndex:0];
  [self waitForExpectations:@[timedOut] timeout:2];

  XCTestExpectation *fresh = [self expectationWithDescription:@"fresh operation completes"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(QONRemoteConfigV2FetchResult *result) {
    XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindFetched);
    [fresh fulfill];
  }];
  XCTAssertEqual(transport.requests.count, 2u);
  XCTAssertEqual(core.admissions, 2u);
  transport.completions[0]([QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"old"]);
  transport.completions[1]([QONRemoteConfigV2FetchResponse successWithBody:[NSData data]
      strongETag:@"fresh"]);
  [self waitForExpectations:@[fresh] timeout:2];
  XCTAssertEqual(core.admittedBodies, 1u);
}

- (void)testInvalid304RetriesExactlyOnceWithoutETag {
  QONRemoteConfigV2FetchTestCore *core = [QONRemoteConfigV2FetchTestCore new];
  core.validator = [[QONRemoteConfigV2ConditionalRequestValidator alloc]
      initWithStrongETag:@"\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
      bodyDigest:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      headAdmissionOrdinal:1];
  QONRemoteConfigV2FetchTestTransport *transport = [QONRemoteConfigV2FetchTestTransport new];
  QONRemoteConfigV2FetchTestPolicyStore *store = [QONRemoteConfigV2FetchTestPolicyStore new];
  QONRemoteConfigV2FetchTestClock *clock = [QONRemoteConfigV2FetchTestClock new];
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:0 timeoutMilliseconds:nil
      initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000];
  QONRemoteConfigV2FetchCoordinator *coordinator = [self coordinatorWithCore:core
      transport:transport store:store clock:clock policy:policy];
  [coordinator transitionToBinding:[self bindingForUser:@"user"]];
  XCTestExpectation *done = [self expectationWithDescription:@"invalid 304"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(QONRemoteConfigV2FetchResult *result) {
    XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindInvalidNotModified);
    [done fulfill];
  }];
  XCTAssertNotNil(transport.requests[0].ifNoneMatch);
  core.validator = nil;
  transport.completions[0]([QONRemoteConfigV2FetchResponse notModifiedWithStrongETag:nil]);
  XCTAssertEqual(transport.requests.count, 2u);
  XCTAssertNil(transport.requests[1].ifNoneMatch);
  transport.completions[1]([QONRemoteConfigV2FetchResponse notModifiedWithStrongETag:nil]);
  [self waitForExpectations:@[done] timeout:2];
  XCTAssertEqual(transport.requests.count, 2u);
}

- (void)testPolicySaveFailureIsExplicitObservableAndConservativeInProcess {
  QONRemoteConfigV2FetchTestCore *core = [QONRemoteConfigV2FetchTestCore new];
  QONRemoteConfigV2FetchTestTransport *transport = [QONRemoteConfigV2FetchTestTransport new];
  QONRemoteConfigV2FetchTestPolicyStore *store = [QONRemoteConfigV2FetchTestPolicyStore new];
  store.saveSucceeds = NO;
  QONRemoteConfigV2FetchTestClock *clock = [QONRemoteConfigV2FetchTestClock new];
  clock.now = 1000;
  dispatch_queue_t callbacks = dispatch_queue_create("io.qonversion.fetch-save-tests", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger observations = 0;
  QONRemoteConfigV2FetchCoordinator *coordinator = [[QONRemoteConfigV2FetchCoordinator alloc]
      initWithCore:core transport:transport policyStore:store clock:clock
      random:[QONRemoteConfigV2FetchTestRandom new]
      scheduler:[QONRemoteConfigV2FetchTestScheduler new]
      policy:[[QONRemoteConfigV2FetchPolicy alloc] initWithMinimumFetchIntervalMilliseconds:0
          timeoutMilliseconds:nil initialBackoffMilliseconds:1000 maximumBackoffMilliseconds:60000]
      callbackExecutor:callbacks policyPersistenceFailureObserver:^(__unused id scope,
          __unused QONRemoteConfigV2FetchPolicyFailureReason reason) { observations += 1; }];
  [coordinator transitionToBinding:[self bindingForUser:@"user"]];
  XCTestExpectation *failed = [self expectationWithDescription:@"save failed"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
      completion:^(QONRemoteConfigV2FetchResult *result) {
    XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed);
    [failed fulfill];
  }];
  transport.completions[0]([QONRemoteConfigV2FetchResponse failureWithStatusCode:@503
      retryAfterMilliseconds:@5000]);
  [self waitForExpectations:@[failed] timeout:2];
  XCTAssertEqual(observations, 1u);
  XCTestExpectation *gated = [self expectationWithDescription:@"in-process backoff"];
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonLogout
      completion:^(QONRemoteConfigV2FetchResult *result) {
    XCTAssertEqual(result.kind, QONRemoteConfigV2FetchResultKindBackoff);
    [gated fulfill];
  }];
  [self waitForExpectations:@[gated] timeout:2];
  XCTAssertEqual(transport.requests.count, 1u);
}

@end
