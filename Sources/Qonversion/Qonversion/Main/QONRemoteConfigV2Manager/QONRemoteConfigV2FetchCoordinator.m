#import "QONRemoteConfigV2FetchCoordinator.h"
#import <math.h>

static NSInteger const QONRemoteConfigV2FetchMaximumFailureCount = 63;
static double const QONRemoteConfigV2FetchFallbackJitter = 0.5;

static int64_t QONRemoteConfigV2FetchSaturatingAdd(int64_t left, int64_t right) {
  if (right > 0 && left > INT64_MAX - right) return INT64_MAX;
  return left + right;
}

@implementation QONRemoteConfigV2ConditionalRequestValidator

- (instancetype)initWithStrongETag:(NSString *)strongETag
                          bodyDigest:(NSString *)bodyDigest
            headAdmissionOrdinal:(int64_t)headAdmissionOrdinal {
  if (strongETag.length == 0 || bodyDigest.length != 64 || headAdmissionOrdinal <= 0) return nil;
  self = [super init];
  if (self) {
    _strongETag = [strongETag copy];
    _bodyDigest = [bodyDigest copy];
    _headAdmissionOrdinal = headAdmissionOrdinal;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)hash {
  return self.strongETag.hash ^ self.bodyDigest.hash ^ (NSUInteger)self.headAdmissionOrdinal;
}
- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2ConditionalRequestValidator.class]) return NO;
  QONRemoteConfigV2ConditionalRequestValidator *other = object;
  return self.headAdmissionOrdinal == other.headAdmissionOrdinal &&
      [self.strongETag isEqualToString:other.strongETag] &&
      [self.bodyDigest isEqualToString:other.bodyDigest];
}

@end

@implementation QONRemoteConfigV2FetchBinding

- (instancetype)initWithScope:(QONRemoteConfigV2Scope *)scope
                    expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation {
  if (!scope || !expectation || ![scope.environment isEqualToString:expectation.environmentUID]) return nil;
  self = [super init];
  if (self) {
    _scope = [scope copy];
    _expectation = [expectation copy];
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }

@end

@implementation QONRemoteConfigV2FetchPolicy

- (instancetype)initWithMinimumFetchIntervalMilliseconds:(int64_t)minimumFetchIntervalMilliseconds
                                       timeoutMilliseconds:(NSNumber *)timeoutMilliseconds
                                initialBackoffMilliseconds:(int64_t)initialBackoffMilliseconds
                                maximumBackoffMilliseconds:(int64_t)maximumBackoffMilliseconds {
  if (minimumFetchIntervalMilliseconds < 0 ||
      (timeoutMilliseconds && timeoutMilliseconds.longLongValue <= 0) ||
      initialBackoffMilliseconds <= 0 || maximumBackoffMilliseconds < initialBackoffMilliseconds) return nil;
  self = [super init];
  if (self) {
    _minimumFetchIntervalMilliseconds = minimumFetchIntervalMilliseconds;
    _timeoutMilliseconds = [timeoutMilliseconds copy];
    _initialBackoffMilliseconds = initialBackoffMilliseconds;
    _maximumBackoffMilliseconds = maximumBackoffMilliseconds;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }

@end

@implementation QONRemoteConfigV2FetchPolicyState

- (instancetype)initWithLastSuccessfulFetchAtMilliseconds:(int64_t)lastSuccessfulFetchAtMilliseconds
                              consecutiveRetryableFailures:(NSInteger)consecutiveRetryableFailures
                            nextAllowedFetchAtMilliseconds:(int64_t)nextAllowedFetchAtMilliseconds {
  if (lastSuccessfulFetchAtMilliseconds < 0 || consecutiveRetryableFailures < 0 ||
      consecutiveRetryableFailures > QONRemoteConfigV2FetchMaximumFailureCount ||
      nextAllowedFetchAtMilliseconds < 0) return nil;
  self = [super init];
  if (self) {
    _lastSuccessfulFetchAtMilliseconds = lastSuccessfulFetchAtMilliseconds;
    _consecutiveRetryableFailures = consecutiveRetryableFailures;
    _nextAllowedFetchAtMilliseconds = nextAllowedFetchAtMilliseconds;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }

@end

@implementation QONRemoteConfigV2FetchPolicyLoadResult

- (instancetype)initWithStatus:(QONRemoteConfigV2FetchPolicyLoadStatus)status
                          state:(QONRemoteConfigV2FetchPolicyState *)state {
  if (status < QONRemoteConfigV2FetchPolicyLoadStatusFound ||
      status > QONRemoteConfigV2FetchPolicyLoadStatusCorrupt) return nil;
  if ((status == QONRemoteConfigV2FetchPolicyLoadStatusFound) != (state != nil)) return nil;
  self = [super init];
  if (self) {
    _status = status;
    _state = state;
  }
  return self;
}

@end

@implementation QONRemoteConfigV2FetchPolicyScope

- (instancetype)initWithProjectKey:(NSString *)projectKey environment:(NSString *)environment {
  if (projectKey.length == 0 || environment.length == 0) return nil;
  self = [super init];
  if (self) {
    _projectKey = [projectKey copy];
    _environment = [environment copy];
  }
  return self;
}
+ (instancetype)scopeFromRemoteConfigScope:(QONRemoteConfigV2Scope *)scope {
  return [[self alloc] initWithProjectKey:scope.projectKey environment:scope.environment];
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)hash { return self.projectKey.hash ^ self.environment.hash; }
- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2FetchPolicyScope.class]) return NO;
  QONRemoteConfigV2FetchPolicyScope *other = object;
  return [self.projectKey isEqualToString:other.projectKey] &&
      [self.environment isEqualToString:other.environment];
}

@end

@implementation QONRemoteConfigV2FetchRequest
- (instancetype)initWithIfNoneMatch:(NSString *)ifNoneMatch {
  self = [super init];
  if (self) _ifNoneMatch = [ifNoneMatch copy];
  return self;
}
@end

@interface QONRemoteConfigV2FetchResponse ()
@property (nonatomic, assign, readwrite) QONRemoteConfigV2FetchResponseKind kind;
@property (nonatomic, copy, nullable, readwrite) NSData *body;
@property (nonatomic, copy, nullable, readwrite) NSString *strongETag;
@property (nonatomic, strong, nullable, readwrite) NSNumber *statusCode;
@property (nonatomic, strong, nullable, readwrite) NSNumber *retryAfterMilliseconds;
@end

@implementation QONRemoteConfigV2FetchResponse

+ (instancetype)successWithBody:(NSData *)body strongETag:(NSString *)strongETag {
  QONRemoteConfigV2FetchResponse *response = [self new];
  response.kind = QONRemoteConfigV2FetchResponseKindSuccess;
  response.body = [body copy];
  response.strongETag = [strongETag copy];
  return response;
}
+ (instancetype)notModifiedWithStrongETag:(NSString *)strongETag {
  QONRemoteConfigV2FetchResponse *response = [self new];
  response.kind = QONRemoteConfigV2FetchResponseKindNotModified;
  response.strongETag = [strongETag copy];
  return response;
}
+ (instancetype)failureWithStatusCode:(NSNumber *)statusCode
                retryAfterMilliseconds:(NSNumber *)retryAfterMilliseconds {
  QONRemoteConfigV2FetchResponse *response = [self new];
  response.kind = QONRemoteConfigV2FetchResponseKindFailure;
  response.statusCode = [statusCode copy];
  response.retryAfterMilliseconds = [retryAfterMilliseconds copy];
  return response;
}

@end

@interface QONRemoteConfigV2FetchResult ()
@property (nonatomic, assign, readwrite) QONRemoteConfigV2FetchResultKind kind;
@property (nonatomic, assign, readwrite) QONRemoteConfigV2TransitionStatus transitionStatus;
@property (nonatomic, strong, nullable, readwrite) NSNumber *statusCode;
@property (nonatomic, assign, readwrite) int64_t nextAllowedAtMilliseconds;
@property (nonatomic, strong, nullable, readwrite) QONRemoteConfigSnapshot *snapshot;
@property (nonatomic, strong, nullable, readwrite) QONRemoteConfigV2FetchResult *underlyingResult;
@property (nonatomic, assign, readwrite) QONRemoteConfigV2FetchPolicyFailureReason policyFailureReason;
@end

@implementation QONRemoteConfigV2FetchResult
@end

@interface QONRemoteConfigV2FetchWaiter : NSObject
@property (nonatomic, copy) QONRemoteConfigV2FetchCompletion callback;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduledTask> timeoutTask;
@property (nonatomic, assign) BOOL terminalClaimed;
@end
@implementation QONRemoteConfigV2FetchWaiter
@end

@interface QONRemoteConfigV2FetchOperation : NSObject
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) QONRemoteConfigV2FetchBinding *binding;
@property (nonatomic, strong) QONRemoteConfigV2AdmissionToken *admission;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2FetchWaiter *> *waiters;
@property (nonatomic, strong, nullable) QONRemoteConfigV2ConditionalRequestValidator *validator;
@property (nonatomic, assign) NSUInteger attemptOrdinal;
@property (nonatomic, assign) BOOL didRetryWithoutETag;
@property (nonatomic, strong) QONRemoteConfigV2FetchPolicyScope *policyScope;
@end
@implementation QONRemoteConfigV2FetchOperation
@end

@interface QONRemoteConfigV2FetchDelivery : NSObject
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) QONRemoteConfigV2FetchWaiter *waiter;
@property (nonatomic, strong) QONRemoteConfigV2FetchResult *result;
@end
@implementation QONRemoteConfigV2FetchDelivery
@end

@interface QONRemoteConfigV2FetchDecision : NSObject
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchResult *immediateResult;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchOperation *operation;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchWaiter *waiter;
@property (nonatomic, assign) BOOL shouldStart;
@end
@implementation QONRemoteConfigV2FetchDecision
@end

@interface QONRemoteConfigV2FetchOutcome : NSObject
@property (nonatomic, strong) QONRemoteConfigV2FetchResult *result;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchPolicyState *nextPolicyState;
@end
@implementation QONRemoteConfigV2FetchOutcome
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2NotModifiedDisposition) {
  QONRemoteConfigV2NotModifiedDispositionNotApplicable,
  QONRemoteConfigV2NotModifiedDispositionAccept,
  QONRemoteConfigV2NotModifiedDispositionRetry,
  QONRemoteConfigV2NotModifiedDispositionReject,
  QONRemoteConfigV2NotModifiedDispositionIgnore,
};

@interface QONRemoteConfigV2FetchCoordinator ()
@property (nonatomic, strong) id<QONRemoteConfigV2FetchCore> core;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchTransport> transport;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchPolicyStoring> policyStore;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchClock> clock;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchRandom> random;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchScheduler> scheduler;
@property (nonatomic, strong) QONRemoteConfigV2FetchPolicy *policy;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) dispatch_queue_t callbackExecutor;
@property (nonatomic, strong) NSObject *callbackExecutorToken;
@property (nonatomic, assign) BOOL callbackExecutorIsMain;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchPolicyPersistenceFailureObserver failureObserver;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchBinding *binding;
@property (nonatomic, assign) NSUInteger operationGeneration;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchOperation *inFlight;
@property (nonatomic, strong) QONRemoteConfigV2FetchPolicyState *policyState;
@property (nonatomic, strong, nullable) NSNumber *pendingPolicyFailureReason;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2FetchDelivery *> *pendingDeliveries;
@property (nonatomic, assign) BOOL isDrainingDeliveries;
@end

@implementation QONRemoteConfigV2FetchCoordinator

- (instancetype)initWithCore:(id<QONRemoteConfigV2FetchCore>)core
                    transport:(id<QONRemoteConfigV2FetchTransport>)transport
                  policyStore:(id<QONRemoteConfigV2FetchPolicyStoring>)policyStore
                        clock:(id<QONRemoteConfigV2FetchClock>)clock
                       random:(id<QONRemoteConfigV2FetchRandom>)random
                    scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                       policy:(QONRemoteConfigV2FetchPolicy *)policy {
  return [self initWithCore:core transport:transport policyStore:policyStore clock:clock
      random:random scheduler:scheduler policy:policy callbackExecutor:dispatch_get_main_queue()
      policyPersistenceFailureObserver:nil];
}

- (instancetype)initWithCore:(id<QONRemoteConfigV2FetchCore>)core
                    transport:(id<QONRemoteConfigV2FetchTransport>)transport
                  policyStore:(id<QONRemoteConfigV2FetchPolicyStoring>)policyStore
                        clock:(id<QONRemoteConfigV2FetchClock>)clock
                       random:(id<QONRemoteConfigV2FetchRandom>)random
                    scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                       policy:(QONRemoteConfigV2FetchPolicy *)policy
             callbackExecutor:(dispatch_queue_t)callbackExecutor
 policyPersistenceFailureObserver:(QONRemoteConfigV2FetchPolicyPersistenceFailureObserver)observer {
  if (!core || !transport || !policyStore || !clock || !random || !scheduler || !policy || !callbackExecutor) {
    return nil;
  }
  self = [super init];
  if (self) {
    _core = core;
    _transport = transport;
    _policyStore = policyStore;
    _clock = clock;
    _random = random;
    _scheduler = scheduler;
    _policy = [policy copy];
    _stateQueue = dispatch_queue_create("io.qonversion.remote-config-v2-fetch-state", DISPATCH_QUEUE_SERIAL);
    _callbackExecutor = callbackExecutor;
    _callbackExecutorToken = [NSObject new];
    _callbackExecutorIsMain = callbackExecutor == dispatch_get_main_queue();
    const void *key = (__bridge const void *)_callbackExecutorToken;
    dispatch_queue_set_specific(callbackExecutor, key, (void *)key, NULL);
    _failureObserver = [observer copy];
    _policyState = [[QONRemoteConfigV2FetchPolicyState alloc]
        initWithLastSuccessfulFetchAtMilliseconds:0 consecutiveRetryableFailures:0
        nextAllowedFetchAtMilliseconds:0];
    _pendingDeliveries = [NSMutableArray new];
  }
  return self;
}

- (QONRemoteConfigV2FetchResult *)resultWithKind:(QONRemoteConfigV2FetchResultKind)kind {
  QONRemoteConfigV2FetchResult *result = [QONRemoteConfigV2FetchResult new];
  result.kind = kind;
  result.transitionStatus = QONRemoteConfigV2TransitionStatusRejected;
  return result;
}

- (QONRemoteConfigV2FetchResult *)supersededResult {
  return [self resultWithKind:QONRemoteConfigV2FetchResultKindSuperseded];
}

- (int64_t)nowMilliseconds {
  @try { return MAX((int64_t)0, [self.clock nowMilliseconds]); }
  @catch (__unused NSException *exception) { return 0; }
}

- (BOOL)savePolicyState:(QONRemoteConfigV2FetchPolicyState *)state
                   scope:(QONRemoteConfigV2FetchPolicyScope *)scope {
  @try { return [self.policyStore saveState:state forScope:scope]; }
  @catch (__unused NSException *exception) { return NO; }
}

- (QONRemoteConfigV2FetchPolicyState *)conservativePolicyState {
  int64_t now = [self nowMilliseconds];
  return [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:0 consecutiveRetryableFailures:1
      nextAllowedFetchAtMilliseconds:QONRemoteConfigV2FetchSaturatingAdd(
          now, self.policy.initialBackoffMilliseconds)];
}

- (QONRemoteConfigV2FetchPolicyState *)loadPolicyState:(QONRemoteConfigV2FetchPolicyScope *)scope
                                         failureReason:(NSNumber **)failureReason {
  QONRemoteConfigV2FetchPolicyLoadResult *loadResult = nil;
  @try { loadResult = [self.policyStore loadResultForScope:scope]; }
  @catch (__unused NSException *exception) {
    loadResult = [[QONRemoteConfigV2FetchPolicyLoadResult alloc]
        initWithStatus:QONRemoteConfigV2FetchPolicyLoadStatusFailed state:nil];
  }
  if (!loadResult || loadResult.status == QONRemoteConfigV2FetchPolicyLoadStatusFailed) {
    if (failureReason) *failureReason = @(QONRemoteConfigV2FetchPolicyFailureReasonLoadFailed);
    return [self conservativePolicyState];
  }
  if (loadResult.status == QONRemoteConfigV2FetchPolicyLoadStatusCorrupt) {
    if (failureReason) *failureReason = @(QONRemoteConfigV2FetchPolicyFailureReasonLoadCorrupt);
    return [self conservativePolicyState];
  }
  if (loadResult.status == QONRemoteConfigV2FetchPolicyLoadStatusMissing) {
    return [[QONRemoteConfigV2FetchPolicyState alloc]
        initWithLastSuccessfulFetchAtMilliseconds:0 consecutiveRetryableFailures:0
        nextAllowedFetchAtMilliseconds:0];
  }
  QONRemoteConfigV2FetchPolicyState *loaded = loadResult.state;
  if (!loaded) {
    if (failureReason) *failureReason = @(QONRemoteConfigV2FetchPolicyFailureReasonLoadCorrupt);
    return [self conservativePolicyState];
  }
  int64_t latest = QONRemoteConfigV2FetchSaturatingAdd([self nowMilliseconds],
      self.policy.maximumBackoffMilliseconds);
  if (loaded.nextAllowedFetchAtMilliseconds <= latest) return loaded;
  QONRemoteConfigV2FetchPolicyState *sanitized = [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:loaded.lastSuccessfulFetchAtMilliseconds
      consecutiveRetryableFailures:loaded.consecutiveRetryableFailures
      nextAllowedFetchAtMilliseconds:latest];
  if (![self savePolicyState:sanitized scope:scope] && failureReason) {
    *failureReason = @(QONRemoteConfigV2FetchPolicyFailureReasonSave);
  }
  return sanitized;
}

- (void)observePersistenceFailureForScope:(QONRemoteConfigV2FetchPolicyScope *)scope
                                    reason:(QONRemoteConfigV2FetchPolicyFailureReason)reason {
  QONRemoteConfigV2FetchPolicyPersistenceFailureObserver observer = self.failureObserver;
  if (!observer) return;
  @try { observer(scope, reason); }
  @catch (__unused NSException *exception) {}
}

- (void)transitionToBinding:(QONRemoteConfigV2FetchBinding *)binding {
  __block QONRemoteConfigV2FetchPolicyScope *failedScope = nil;
  __block NSNumber *failureReason = nil;
  QONRemoteConfigV2FetchBinding *bindingCopy = [binding copy];
  dispatch_sync(self.stateQueue, ^{
    self.operationGeneration = self.operationGeneration == NSUIntegerMax ? 0 : self.operationGeneration + 1;
    self.binding = bindingCopy;
    [self.core setScope:bindingCopy.scope];
    if (bindingCopy) {
      QONRemoteConfigV2FetchPolicyScope *scope = [QONRemoteConfigV2FetchPolicyScope
          scopeFromRemoteConfigScope:bindingCopy.scope];
      self.policyState = [self loadPolicyState:scope failureReason:&failureReason];
      self.pendingPolicyFailureReason = failureReason;
      if (failureReason) failedScope = scope;
    } else {
      self.policyState = [[QONRemoteConfigV2FetchPolicyState alloc]
          initWithLastSuccessfulFetchAtMilliseconds:0 consecutiveRetryableFailures:0
          nextAllowedFetchAtMilliseconds:0];
      self.pendingPolicyFailureReason = nil;
    }
    QONRemoteConfigV2FetchOperation *operation = self.inFlight;
    if (operation) {
      for (QONRemoteConfigV2FetchWaiter *waiter in operation.waiters) {
        if (waiter.terminalClaimed) continue;
        waiter.terminalClaimed = YES;
        QONRemoteConfigV2FetchDelivery *delivery = [QONRemoteConfigV2FetchDelivery new];
        delivery.generation = operation.generation;
        delivery.waiter = waiter;
        delivery.result = [self supersededResult];
        [self.pendingDeliveries addObject:delivery];
      }
      [operation.waiters removeAllObjects];
    }
    self.inFlight = nil;
  });
  if (failedScope) [self observePersistenceFailureForScope:failedScope
      reason:failureReason.integerValue];
  [self drainDeliveries];
}

- (QONRemoteConfigV2FetchResult *)gateResultForForceReason:(QONRemoteConfigV2FetchForceReason)forceReason
                                                       now:(int64_t)now {
  if (now < self.policyState.nextAllowedFetchAtMilliseconds) {
    QONRemoteConfigV2FetchResult *result = [self resultWithKind:QONRemoteConfigV2FetchResultKindBackoff];
    result.nextAllowedAtMilliseconds = self.policyState.nextAllowedFetchAtMilliseconds;
    return result;
  }
  if (forceReason == QONRemoteConfigV2FetchForceReasonNone &&
      self.policyState.lastSuccessfulFetchAtMilliseconds > 0 &&
      now >= self.policyState.lastSuccessfulFetchAtMilliseconds) {
    int64_t next = QONRemoteConfigV2FetchSaturatingAdd(
        self.policyState.lastSuccessfulFetchAtMilliseconds,
        self.policy.minimumFetchIntervalMilliseconds);
    if (now < next) {
      QONRemoteConfigV2FetchResult *result = [self resultWithKind:
          QONRemoteConfigV2FetchResultKindMinimumInterval];
      result.nextAllowedAtMilliseconds = next;
      return result;
    }
  }
  return nil;
}

- (QONRemoteConfigV2FetchWaiter *)waiterWithCallback:(QONRemoteConfigV2FetchCompletion)callback {
  QONRemoteConfigV2FetchWaiter *waiter = [QONRemoteConfigV2FetchWaiter new];
  waiter.callback = [callback copy];
  return waiter;
}

- (QONRemoteConfigV2FetchDecision *)decisionForForceReason:(QONRemoteConfigV2FetchForceReason)forceReason
                                                   callback:(QONRemoteConfigV2FetchCompletion)callback {
  QONRemoteConfigV2FetchDecision *decision = [QONRemoteConfigV2FetchDecision new];
  decision.generation = self.operationGeneration;
  if (self.inFlight) {
    BOOL hasLiveWaiter = NO;
    for (QONRemoteConfigV2FetchWaiter *waiter in self.inFlight.waiters) {
      if (!waiter.terminalClaimed) { hasLiveWaiter = YES; break; }
    }
    if (hasLiveWaiter) {
      decision.operation = self.inFlight;
      decision.waiter = [self waiterWithCallback:callback];
      [self.inFlight.waiters addObject:decision.waiter];
      return decision;
    }
    // The old HTTP continues, but the next caller owns a fresh admission token.
    self.inFlight = nil;
  }
  if (!self.binding) {
    decision.immediateResult = [self supersededResult];
    return decision;
  }
  if (self.pendingPolicyFailureReason) {
    QONRemoteConfigV2FetchResult *failure = [self resultWithKind:
        QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed];
    failure.policyFailureReason = self.pendingPolicyFailureReason.integerValue;
    failure.nextAllowedAtMilliseconds = self.policyState.nextAllowedFetchAtMilliseconds;
    QONRemoteConfigV2FetchResult *backoff = [self resultWithKind:QONRemoteConfigV2FetchResultKindBackoff];
    backoff.nextAllowedAtMilliseconds = self.policyState.nextAllowedFetchAtMilliseconds;
    failure.underlyingResult = backoff;
    self.pendingPolicyFailureReason = nil;
    decision.immediateResult = failure;
    return decision;
  }
  QONRemoteConfigV2FetchResult *gate = [self gateResultForForceReason:forceReason
      now:[self nowMilliseconds]];
  if (gate) {
    decision.immediateResult = gate;
    return decision;
  }
  QONRemoteConfigV2AdmissionToken *admission = [self.core beginAdmissionForScope:self.binding.scope
      expectation:self.binding.expectation];
  if (!admission) {
    QONRemoteConfigV2FetchResult *failed = [self resultWithKind:QONRemoteConfigV2FetchResultKindFailed];
    decision.immediateResult = failed;
    return decision;
  }
  QONRemoteConfigV2FetchOperation *operation = [QONRemoteConfigV2FetchOperation new];
  operation.generation = self.operationGeneration;
  operation.binding = self.binding;
  operation.admission = admission;
  operation.waiters = [NSMutableArray new];
  operation.validator = [self.core conditionalRequestValidator];
  operation.policyScope = [QONRemoteConfigV2FetchPolicyScope
      scopeFromRemoteConfigScope:self.binding.scope];
  decision.operation = operation;
  decision.waiter = [self waiterWithCallback:callback];
  [operation.waiters addObject:decision.waiter];
  decision.shouldStart = YES;
  self.inFlight = operation;
  return decision;
}

- (void)fetchWithForceReason:(QONRemoteConfigV2FetchForceReason)forceReason
                   completion:(QONRemoteConfigV2FetchCompletion)completion {
  if (!completion) return;
  __block QONRemoteConfigV2FetchDecision *decision = nil;
  dispatch_sync(self.stateQueue, ^{
    decision = [self decisionForForceReason:forceReason callback:completion];
  });
  if (decision.immediateResult) {
    dispatch_sync(self.stateQueue, ^{
      QONRemoteConfigV2FetchWaiter *waiter = [self waiterWithCallback:completion];
      waiter.terminalClaimed = YES;
      QONRemoteConfigV2FetchDelivery *delivery = [QONRemoteConfigV2FetchDelivery new];
      delivery.generation = decision.generation;
      delivery.waiter = waiter;
      delivery.result = decision.generation == self.operationGeneration
          ? decision.immediateResult : [self supersededResult];
      [self.pendingDeliveries addObject:delivery];
    });
    [self drainDeliveries];
    return;
  }
  [self scheduleTimeoutForOperation:decision.operation waiter:decision.waiter];
  if (decision.shouldStart) [self startAttempt:decision.operation];
}

- (void)scheduleTimeoutForOperation:(QONRemoteConfigV2FetchOperation *)operation
                              waiter:(QONRemoteConfigV2FetchWaiter *)waiter {
  NSNumber *timeout = self.policy.timeoutMilliseconds;
  if (!timeout) return;
  id<QONRemoteConfigV2FetchScheduledTask> task = nil;
  @try {
    __weak typeof(self) weakSelf = self;
    task = [self.scheduler scheduleAfterMilliseconds:timeout.longLongValue action:^{
      [weakSelf timeoutOperation:operation waiter:waiter];
    }];
  } @catch (__unused NSException *exception) { return; }
  __block BOOL retained = NO;
  dispatch_sync(self.stateQueue, ^{
    if (self.inFlight == operation && operation.generation == self.operationGeneration &&
        !waiter.terminalClaimed && [operation.waiters containsObject:waiter]) {
      waiter.timeoutTask = task;
      retained = YES;
    }
  });
  if (!retained) [self cancelTaskSafely:task];
}

- (void)timeoutOperation:(QONRemoteConfigV2FetchOperation *)operation
                   waiter:(QONRemoteConfigV2FetchWaiter *)waiter {
  dispatch_sync(self.stateQueue, ^{
    if (self.inFlight != operation || operation.generation != self.operationGeneration ||
        waiter.terminalClaimed || ![operation.waiters containsObject:waiter]) return;
    [operation.waiters removeObject:waiter];
    waiter.terminalClaimed = YES;
    QONRemoteConfigV2FetchResult *result = [self resultWithKind:QONRemoteConfigV2FetchResultKindTimedOut];
    result.snapshot = [self.core currentSnapshot];
    QONRemoteConfigV2FetchDelivery *delivery = [QONRemoteConfigV2FetchDelivery new];
    delivery.generation = operation.generation;
    delivery.waiter = waiter;
    delivery.result = result;
    [self.pendingDeliveries addObject:delivery];
  });
  [self drainDeliveries];
}

- (void)startAttempt:(QONRemoteConfigV2FetchOperation *)operation {
  __block QONRemoteConfigV2FetchRequest *request = nil;
  __block NSUInteger attempt = 0;
  dispatch_sync(self.stateQueue, ^{
    if (self.inFlight != operation || operation.generation != self.operationGeneration) return;
    operation.attemptOrdinal += 1;
    attempt = operation.attemptOrdinal;
    request = [[QONRemoteConfigV2FetchRequest alloc]
        initWithIfNoneMatch:operation.validator.strongETag];
  });
  if (!request) return;
  @try {
    __weak typeof(self) weakSelf = self;
    [self.transport fetchRequest:request completion:^(QONRemoteConfigV2FetchResponse *response) {
      QONRemoteConfigV2FetchResponse *safeResponse = response ?: [QONRemoteConfigV2FetchResponse
          failureWithStatusCode:nil retryAfterMilliseconds:nil];
      [weakSelf completeOperation:operation attempt:attempt response:safeResponse];
    }];
  } @catch (__unused NSException *exception) {
    [self completeOperation:operation attempt:attempt response:[QONRemoteConfigV2FetchResponse
        failureWithStatusCode:nil retryAfterMilliseconds:nil]];
  }
}

- (BOOL)operationIsCurrent:(QONRemoteConfigV2FetchOperation *)operation attempt:(NSUInteger)attempt {
  return self.inFlight == operation && operation.generation == self.operationGeneration &&
      operation.attemptOrdinal == attempt;
}

- (QONRemoteConfigV2NotModifiedDisposition)notModifiedDispositionForOperation:
    (QONRemoteConfigV2FetchOperation *)operation attempt:(NSUInteger)attempt
    response:(QONRemoteConfigV2FetchResponse *)response {
  if (![self operationIsCurrent:operation attempt:attempt]) {
    return QONRemoteConfigV2NotModifiedDispositionIgnore;
  }
  QONRemoteConfigV2ConditionalRequestValidator *validator = operation.validator;
  BOOL responseMatches = response.strongETag == nil ||
      [response.strongETag isEqualToString:validator.strongETag];
  if (validator && responseMatches && [self.core isConditionalRequestValidatorCurrent:validator]) {
    return QONRemoteConfigV2NotModifiedDispositionAccept;
  }
  if (operation.didRetryWithoutETag) return QONRemoteConfigV2NotModifiedDispositionReject;
  QONRemoteConfigV2AdmissionToken *admission = [self.core beginAdmissionForScope:operation.binding.scope
      expectation:operation.binding.expectation];
  if (!admission) return QONRemoteConfigV2NotModifiedDispositionReject;
  operation.didRetryWithoutETag = YES;
  operation.validator = nil;
  operation.admission = admission;
  return QONRemoteConfigV2NotModifiedDispositionRetry;
}

- (QONRemoteConfigV2FetchPolicyState *)retryableFailureStateFrom:
    (QONRemoteConfigV2FetchPolicyState *)current response:(QONRemoteConfigV2FetchResponse *)response {
  int64_t now = [self nowMilliseconds];
  NSInteger failures = MIN(QONRemoteConfigV2FetchMaximumFailureCount,
                           current.consecutiveRetryableFailures + 1);
  int64_t cap = self.policy.initialBackoffMilliseconds;
  for (NSInteger index = 1; index < failures; index++) {
    if (cap >= self.policy.maximumBackoffMilliseconds / 2) {
      cap = self.policy.maximumBackoffMilliseconds;
      break;
    }
    cap = MIN(self.policy.maximumBackoffMilliseconds, cap * 2);
  }
  double random = QONRemoteConfigV2FetchFallbackJitter;
  @try { random = [self.random nextUnitInterval]; }
  @catch (__unused NSException *exception) {}
  if (!isfinite(random) || random < 0 || random >= 1) random = QONRemoteConfigV2FetchFallbackJitter;
  int64_t delay = MAX((int64_t)1, (int64_t)((double)cap * random));
  if (response.retryAfterMilliseconds && response.retryAfterMilliseconds.longLongValue >= 0) {
    delay = MIN(self.policy.maximumBackoffMilliseconds,
                response.retryAfterMilliseconds.longLongValue);
  }
  return [[QONRemoteConfigV2FetchPolicyState alloc]
      initWithLastSuccessfulFetchAtMilliseconds:current.lastSuccessfulFetchAtMilliseconds
      consecutiveRetryableFailures:failures
      nextAllowedFetchAtMilliseconds:QONRemoteConfigV2FetchSaturatingAdd(now, delay)];
}

- (BOOL)responseIsRetryable:(QONRemoteConfigV2FetchResponse *)response {
  if (!response.statusCode) return YES;
  NSInteger code = response.statusCode.integerValue;
  return code == 429 || code < 400 || code > 499;
}

- (QONRemoteConfigV2FetchOutcome *)outcomeForOperation:(QONRemoteConfigV2FetchOperation *)operation
                                              response:(QONRemoteConfigV2FetchResponse *)response
                           notModifiedDisposition:(QONRemoteConfigV2NotModifiedDisposition)disposition
                                          policyState:(QONRemoteConfigV2FetchPolicyState *)policyState {
  QONRemoteConfigV2FetchOutcome *outcome = [QONRemoteConfigV2FetchOutcome new];
  if (response.kind == QONRemoteConfigV2FetchResponseKindSuccess) {
    QONRemoteConfigV2TransitionStatus status = response.body && response.strongETag
        ? [self.core admitBody:response.body strongETag:response.strongETag
            admissionToken:operation.admission]
        : QONRemoteConfigV2TransitionStatusRejected;
    QONRemoteConfigV2FetchResult *result = [self resultWithKind:QONRemoteConfigV2FetchResultKindFetched];
    result.transitionStatus = status;
    outcome.result = result;
    if (status == QONRemoteConfigV2TransitionStatusAccepted ||
        status == QONRemoteConfigV2TransitionStatusActivated) {
      outcome.nextPolicyState = [[QONRemoteConfigV2FetchPolicyState alloc]
          initWithLastSuccessfulFetchAtMilliseconds:[self nowMilliseconds]
          consecutiveRetryableFailures:0 nextAllowedFetchAtMilliseconds:0];
    }
  } else if (response.kind == QONRemoteConfigV2FetchResponseKindNotModified) {
    if (disposition == QONRemoteConfigV2NotModifiedDispositionAccept) {
      outcome.result = [self resultWithKind:QONRemoteConfigV2FetchResultKindNotModified];
      outcome.nextPolicyState = [[QONRemoteConfigV2FetchPolicyState alloc]
          initWithLastSuccessfulFetchAtMilliseconds:[self nowMilliseconds]
          consecutiveRetryableFailures:0 nextAllowedFetchAtMilliseconds:0];
    } else {
      outcome.result = [self resultWithKind:QONRemoteConfigV2FetchResultKindInvalidNotModified];
    }
  } else {
    QONRemoteConfigV2FetchResult *result = [self resultWithKind:QONRemoteConfigV2FetchResultKindFailed];
    result.statusCode = response.statusCode;
    outcome.result = result;
    if ([self responseIsRetryable:response]) {
      outcome.nextPolicyState = [self retryableFailureStateFrom:policyState response:response];
    }
  }
  return outcome;
}

- (void)completeOperation:(QONRemoteConfigV2FetchOperation *)operation
                  attempt:(NSUInteger)attempt
                 response:(QONRemoteConfigV2FetchResponse *)response {
  __block QONRemoteConfigV2NotModifiedDisposition disposition =
      QONRemoteConfigV2NotModifiedDispositionNotApplicable;
  if (response.kind == QONRemoteConfigV2FetchResponseKindNotModified) {
    dispatch_sync(self.stateQueue, ^{
      disposition = [self notModifiedDispositionForOperation:operation attempt:attempt response:response];
    });
    if (disposition == QONRemoteConfigV2NotModifiedDispositionIgnore) return;
    if (disposition == QONRemoteConfigV2NotModifiedDispositionRetry) {
      [self startAttempt:operation];
      return;
    }
  }
  __block BOOL current = NO;
  __block QONRemoteConfigV2FetchPolicyState *basePolicyState = nil;
  dispatch_sync(self.stateQueue, ^{
    current = [self operationIsCurrent:operation attempt:attempt];
    basePolicyState = self.policyState;
  });
  if (!current) return;
  QONRemoteConfigV2FetchOutcome *outcome = [self outcomeForOperation:operation response:response
      notModifiedDisposition:disposition policyState:basePolicyState];
  __block QONRemoteConfigV2FetchPolicyScope *persistenceFailedScope = nil;
  dispatch_sync(self.stateQueue, ^{
    if (![self operationIsCurrent:operation attempt:attempt]) return;
    QONRemoteConfigV2FetchResult *terminal = outcome.result;
    if (outcome.nextPolicyState) {
      self.policyState = outcome.nextPolicyState;
      if (![self savePolicyState:outcome.nextPolicyState scope:operation.policyScope]) {
        persistenceFailedScope = operation.policyScope;
        QONRemoteConfigV2FetchResult *wrapped = [self resultWithKind:
            QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed];
        wrapped.policyFailureReason = QONRemoteConfigV2FetchPolicyFailureReasonSave;
        wrapped.underlyingResult = outcome.result;
        terminal = wrapped;
      }
    }
    self.inFlight = nil;
    for (QONRemoteConfigV2FetchWaiter *waiter in operation.waiters) {
      if (waiter.terminalClaimed) continue;
      waiter.terminalClaimed = YES;
      QONRemoteConfigV2FetchDelivery *delivery = [QONRemoteConfigV2FetchDelivery new];
      delivery.generation = operation.generation;
      delivery.waiter = waiter;
      delivery.result = terminal;
      [self.pendingDeliveries addObject:delivery];
    }
    [operation.waiters removeAllObjects];
  });
  if (persistenceFailedScope) [self observePersistenceFailureForScope:persistenceFailedScope
      reason:QONRemoteConfigV2FetchPolicyFailureReasonSave];
  [self drainDeliveries];
}

- (BOOL)isOnCallbackExecutor {
  if (self.callbackExecutorIsMain && NSThread.isMainThread) return YES;
  const void *key = (__bridge const void *)self.callbackExecutorToken;
  return dispatch_get_specific(key) == key;
}

- (void)cancelTaskSafely:(id<QONRemoteConfigV2FetchScheduledTask>)task {
  if (!task) return;
  @try { [task cancel]; }
  @catch (__unused NSException *exception) {}
}

- (void)drainDeliveriesOnCallbackExecutor {
  NSAssert([self isOnCallbackExecutor], @"Remote Config fetch callback executor must be serial");
  if (self.isDrainingDeliveries) return;
  self.isDrainingDeliveries = YES;
  @try {
    while (YES) {
      __block QONRemoteConfigV2FetchDelivery *delivery = nil;
      dispatch_sync(self.stateQueue, ^{
        if (self.pendingDeliveries.count == 0) return;
        delivery = self.pendingDeliveries.firstObject;
        [self.pendingDeliveries removeObjectAtIndex:0];
        if (delivery.generation != self.operationGeneration) delivery.result = [self supersededResult];
      });
      if (!delivery) return;
      [self cancelTaskSafely:delivery.waiter.timeoutTask];
      @try { delivery.waiter.callback(delivery.result); }
      @catch (__unused NSException *exception) {}
    }
  } @finally {
    self.isDrainingDeliveries = NO;
  }
}

- (void)drainDeliveries {
  if ([self isOnCallbackExecutor]) {
    [self drainDeliveriesOnCallbackExecutor];
  } else {
    dispatch_async(self.callbackExecutor, ^{ [self drainDeliveriesOnCallbackExecutor]; });
  }
}

@end
