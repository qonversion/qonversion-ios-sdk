#import <Foundation/Foundation.h>
#import "QNLocalStorage.h"
#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigV2Store.h"

id QONRemoteConfigPortableJSONObject(NSData *data, NSUInteger maximumBytes) {
  if (!data || data.length == 0 || data.length > maximumBytes) return nil;
  return [NSJSONSerialization JSONObjectWithData:data
      options:NSJSONReadingFragmentsAllowed error:nil];
}

static NSUInteger failures = 0;
static NSUInteger checks = 0;
#define QON_CHECK(condition, message) do { checks += 1; if (!(condition)) { \
  failures += 1; fprintf(stderr, "FAIL: %s\n", message); } } while (0)

@interface GuardStorage : NSObject <QNLocalStorage>
@property(nonatomic, strong) NSMutableDictionary *objects;
@property(nonatomic) NSUInteger reads;
@property(nonatomic) NSUInteger writes;
@property(nonatomic) BOOL failWrites;
@end

@implementation GuardStorage
- (instancetype)init {
  self = [super init];
  if (self) _objects = [NSMutableDictionary new];
  return self;
}
- (void)storeObject:(id)object forKey:(NSString *)key {
  self.writes += 1;
  if (!self.failWrites) self.objects[key] = object;
}
- (id)loadObjectForKey:(NSString *)key {
  self.reads += 1;
  return self.objects[key];
}
- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion([self loadObjectForKey:key]);
}
- (void)removeObjectForKey:(NSString *)key { [self.objects removeObjectForKey:key]; }
@end

@interface GuardBlockingStorage : GuardStorage
@property(nonatomic) BOOL blockNextWrite;
@property(nonatomic, strong) dispatch_semaphore_t writeStarted;
@property(nonatomic, strong) dispatch_semaphore_t releaseWrite;
@end

@implementation GuardBlockingStorage
- (instancetype)init {
  self = [super init];
  if (self) {
    _writeStarted = dispatch_semaphore_create(0);
    _releaseWrite = dispatch_semaphore_create(0);
  }
  return self;
}
- (void)storeObject:(id)object forKey:(NSString *)key {
  if (self.blockNextWrite) {
    self.blockNextWrite = NO;
    dispatch_semaphore_signal(self.writeStarted);
    dispatch_semaphore_wait(self.releaseWrite,
                            dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
  }
  [super storeObject:object forKey:key];
}
@end

@interface GuardPreloader : NSObject <QONRemoteConfigV2ScopePreloading>
@property(nonatomic, strong) QONRemoteConfigV2ReadGuardPreloadResult *result;
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL observedMainThread;
@end

@implementation GuardPreloader
- (QONRemoteConfigV2ReadGuardPreloadResult *)preloadResultForScope:
    (__unused QONRemoteConfigV2Scope *)scope {
  self.calls += 1;
  self.observedMainThread = NSThread.isMainThread;
  return self.result;
}
@end

@interface GuardAdversarialPreloader : NSObject <QONRemoteConfigV2ScopePreloading>
@property(nonatomic, weak) QONRemoteConfigV2Manager *manager;
@property(nonatomic, strong) QONRemoteConfigV2ReadGuardPreloadResult *resultA;
@property(nonatomic, strong) QONRemoteConfigV2ReadGuardPreloadResult *resultB;
@property(nonatomic, strong) dispatch_semaphore_t firstStarted;
@property(nonatomic, strong) dispatch_semaphore_t releaseFirst;
@property(nonatomic) BOOL waitForSupersedingToken;
@end

@implementation GuardAdversarialPreloader
- (QONRemoteConfigV2ReadGuardPreloadResult *)preloadResultForScope:
    (QONRemoteConfigV2Scope *)scope {
  if (![scope.canonicalUserID isEqualToString:@"user-a"]) return self.resultB;
  NSUUID *initialToken = [self.manager valueForKey:@"latestReadGuardPreloadToken"];
  dispatch_semaphore_signal(self.firstStarted);
  if (self.waitForSupersedingToken) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (deadline.timeIntervalSinceNow > 0) {
      NSUUID *token = [self.manager valueForKey:@"latestReadGuardPreloadToken"];
      if (![token isEqual:initialToken]) break;
      [NSThread sleepForTimeInterval:0.001];
    }
  } else {
    dispatch_semaphore_wait(self.releaseFirst,
                            dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
  }
  return self.resultA;
}
@end

static QONRemoteConfigV2Scope *Scope(NSString *user) {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:@"project"
      environment:@"production" canonicalUserID:user];
}

static QONRemoteConfigV2Release *Release(NSString *uid, NSInteger number, NSString *raw) {
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:data variationUID:[uid stringByAppendingString:@"-key"]
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:@{}];
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:uid releaseNumber:number
      manifestContentHash:[[NSString stringWithFormat:@"%lx", (long)(number % 16)]
          stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:@{@"key": entry}];
}

static QONRemoteConfigV2Release *ImmediateRelease(
    NSString *uid, NSInteger number, NSString *raw) {
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:data variationUID:[uid stringByAppendingString:@"-key"]
      applyPolicy:QONRemoteConfigApplyPolicyImmediate metadata:@{}];
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:uid releaseNumber:number
      manifestContentHash:[[NSString stringWithFormat:@"%lx", (long)(number % 16)]
          stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:@{@"key": entry}];
}

static QONRemoteConfigV2State *CandidateState(NSString *uid, NSInteger number) {
  QONRemoteConfigV2Release *candidate = [Release(uid, number, @"1")
      releaseBySettingAdmissionOrdinal:number];
  return [[QONRemoteConfigV2State alloc] initWithCandidate:candidate
      active:nil previous:nil didActivate:NO latestAdmissionOrdinal:number];
}

static QONRemoteConfigV2State *PendingState(void) {
  QONRemoteConfigV2Release *active = [Release(@"active", 1, @"1")
      releaseBySettingAdmissionOrdinal:1];
  QONRemoteConfigV2Release *candidate = [Release(@"candidate", 2, @"2")
      releaseBySettingAdmissionOrdinal:2];
  return [[QONRemoteConfigV2State alloc] initWithCandidate:candidate active:active
      previous:nil didActivate:YES latestAdmissionOrdinal:2];
}

static QONRemoteConfigV2ReadGuardPreloadResult *PreloadResult(
    QONRemoteConfigV2ReadGuardPreloadStatus status, QONRemoteConfigV2State *state) {
  return [[QONRemoteConfigV2ReadGuardPreloadResult alloc] initWithStatus:status state:state];
}

static QONRemoteConfigV2Manager *Manager(GuardStorage *storage,
    id<QONRemoteConfigV2ScopePreloading> preloader,
    QONRemoteConfigV2ReadGuardBuildMode mode, dispatch_queue_t callbacks,
    QONRemoteConfigV2ReadGuardAssertionHandler assertion,
    QONRemoteConfigV2ReadGuardTelemetryHandler telemetry) {
  return [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:Release(@"bundle", 1, @"0")
      fallbackProjectKey:@"project" fallbackEnvironment:@"production"
      envelopeDecoder:[QONRemoteConfigV2EnvelopeParser new]
      callbackExecutor:callbacks readGuardBuildMode:mode
      assertionHandler:assertion telemetryHandler:telemetry scopePreloader:preloader];
}

static QONRemoteConfigV2ReadGuardPreloadStatus PreloadOffMain(
    QONRemoteConfigV2Manager *manager, QONRemoteConfigV2Scope *scope) {
  __block QONRemoteConfigV2ReadGuardPreloadStatus status =
      QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  dispatch_semaphore_t finished = dispatch_semaphore_create(0);
  dispatch_async(dispatch_queue_create("read.guard.preload", DISPATCH_QUEUE_SERIAL), ^{
    status = [manager preloadScopeForReadGuard:scope];
    dispatch_semaphore_signal(finished);
  });
  dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
  return status;
}

static void Drain(dispatch_queue_t callbacks) { dispatch_sync(callbacks, ^{}); }

static void TestReleaseFirstReadUsesDurablyPreparedCandidateOnlyOnce(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate", 2));
  dispatch_queue_t callbacks = dispatch_queue_create("read.guard.release", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger misuse = 0, implicitActivations = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate) misuse += 1;
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) {
      implicitActivations += 1;
    }
  });
  QONRemoteConfigV2Scope *scope = Scope(@"user");

  QON_CHECK(PreloadOffMain(manager, scope) == QONRemoteConfigV2ReadGuardPreloadStatusFound,
      "valid candidate preload must prepare successfully");
  QON_CHECK(!preloader.observedMainThread, "preloader must run off main before readiness");
  [manager setScope:scope];
  NSUInteger readsBefore = storage.reads, writesBefore = storage.writes;
  QONRemoteConfigSnapshot *first = manager.currentSnapshot;
  QONRemoteConfigSnapshot *second = manager.currentSnapshot;
  Drain(callbacks);

  QON_CHECK([first.releaseUID isEqualToString:@"candidate"] &&
      [second.releaseUID isEqualToString:@"candidate"],
      "release first read must expose the durably prepared candidate");
  QON_CHECK(storage.reads == readsBefore && storage.writes == writesBefore,
      "currentSnapshot getter must perform no storage I/O");
  QON_CHECK(misuse == 1 && implicitActivations == 1,
      "release misuse and confirmed implicit activation must each be emitted once");

  [manager acceptFetchedRelease:Release(@"later", 3, @"2") forScope:scope];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"candidate"],
      "later reads must never implicitly activate a later candidate");
  QON_CHECK([manager.lastFetchedSnapshot.releaseUID isEqualToString:@"later"],
      "later candidate must remain fetched until explicit activation");
}

static void TestFetchAfterPreloadRefreshesDurableFirstReadPreparation(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"preloaded", 1));
  dispatch_queue_t callbacks = dispatch_queue_create(
      "read.guard.fetch-after-preload", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger implicit = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) implicit += 1;
  });
  QONRemoteConfigV2Scope *scope = Scope(@"user");
  PreloadOffMain(manager, scope);
  [manager setScope:scope];
  [manager acceptFetchedRelease:Release(@"fetched", 2, @"2") forScope:scope];

  QONRemoteConfigV2State *durable = nil;
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QON_CHECK([store loadStateForScope:scope state:&durable] ==
      QONRemoteConfigV2StoreLoadStatusFound &&
      [durable.active.releaseUID isEqualToString:@"fetched"],
      "a post-preload fetch must durably refresh the prepared Active before success");
  NSUInteger readsBefore = storage.reads, writesBefore = storage.writes;
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"fetched"],
      "first current must activate the newest post-preload Candidate");
  QON_CHECK(storage.reads == readsBefore && storage.writes == writesBefore,
      "post-preload first current must remain memory-only");
  Drain(callbacks);
  QON_CHECK(implicit == 1, "the refreshed first-read activation must be observable once");
}

static void TestPersistenceRecoveryRearmsAndImmediateDoesNotReportImplicit(void) {
  GuardStorage *storage = [GuardStorage new];
  storage.failWrites = YES;
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   PendingState());
  dispatch_queue_t callbacks = dispatch_queue_create(
      "read.guard.persistence-recovery", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger implicit = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) implicit += 1;
  });
  QONRemoteConfigV2Scope *scope = Scope(@"user");
  QON_CHECK(PreloadOffMain(manager, scope) ==
      QONRemoteConfigV2ReadGuardPreloadStatusPersistenceFailed,
      "the initial prepared write must fail for the recovery scenario");
  [manager setScope:scope];
  storage.failWrites = NO;
  [manager acceptFetchedRelease:Release(@"recovered", 3, @"3") forScope:scope];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"recovered"],
      "a successful later fetch must re-arm first-read activation after persistence recovery");
  Drain(callbacks);
  QON_CHECK(implicit == 1, "recovered first-read activation must be reported once");

  GuardPreloader *missing = [GuardPreloader new];
  missing.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusMissing, nil);
  __block NSUInteger immediateImplicit = 0;
  QONRemoteConfigV2Manager *immediateManager = Manager([GuardStorage new], missing,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) {
      immediateImplicit += 1;
    }
  });
  QONRemoteConfigV2Scope *immediateScope = Scope(@"immediate-user");
  PreloadOffMain(immediateManager, immediateScope);
  [immediateManager setScope:immediateScope];
  [immediateManager acceptFetchedRelease:ImmediateRelease(@"immediate", 2, @"4")
                                forScope:immediateScope];
  QON_CHECK([immediateManager.currentSnapshot.releaseUID isEqualToString:@"immediate"],
      "an immediate release must remain active on first current");
  Drain(callbacks);
  QON_CHECK(immediateImplicit == 0,
      "an already-immediate activation must not be reported as implicit first-read activation");
}

static void TestDebugAssertionIsExactAndNeverImplicitlyActivates(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate", 2));
  dispatch_queue_t callbacks = dispatch_queue_create("read.guard.debug", DISPATCH_QUEUE_SERIAL);
  __block NSString *message = nil;
  __block NSUInteger assertions = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeDebug, callbacks, ^(NSString *value) {
    assertions += 1; message = value;
  }, nil);
  QONRemoteConfigV2Scope *scope = Scope(@"user");
  PreloadOffMain(manager, scope);
  [manager setScope:scope];

  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "debug read-before-activate must remain on the bundle");
  QON_CHECK([message isEqualToString:QONRemoteConfigV2ReadBeforeActivateAssertionMessage] &&
      [message isEqualToString:@"Remote Config read before activate(). Call activate() during SDK startup before reading currentSnapshot."],
      "debug assertion must use the exact actionable contract message");
  (void)manager.currentSnapshot;
  QON_CHECK(assertions == 1, "debug assertion must be bounded once per generation");
  QON_CHECK([manager activate], "explicit activation must remain available after the debug assertion");
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"candidate"],
      "explicit activation must expose the candidate after debug misuse");
}

static void TestUnavailablePreloadsAndPersistenceFailureStayOnPinnedBundle(void) {
  NSArray<NSNumber *> *statuses = @[
    @(QONRemoteConfigV2ReadGuardPreloadStatusMissing),
    @(QONRemoteConfigV2ReadGuardPreloadStatusFailed),
    @(QONRemoteConfigV2ReadGuardPreloadStatusCorrupt),
  ];
  for (NSNumber *statusValue in statuses) {
    GuardStorage *storage = [GuardStorage new];
    GuardPreloader *preloader = [GuardPreloader new];
    QONRemoteConfigV2ReadGuardPreloadStatus status = statusValue.integerValue;
    preloader.result = PreloadResult(status, nil);
    dispatch_queue_t callbacks = dispatch_queue_create("read.guard.fail-safe", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger failSafeEvents = 0, misuseEvents = 0, implicitEvents = 0;
    QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
        QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
        ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
      if (event == QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent ||
          event == QONRemoteConfigV2ReadGuardTelemetryEventPreloadFailed ||
          event == QONRemoteConfigV2ReadGuardTelemetryEventPreloadCorrupt) failSafeEvents += 1;
      if (event == QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate) misuseEvents += 1;
      if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) implicitEvents += 1;
    });
    QONRemoteConfigV2Scope *scope = Scope(@"user");
    QON_CHECK(PreloadOffMain(manager, scope) == status,
        "absent, failed, and corrupt preload results must remain explicit");
    [manager setScope:scope];
    QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
        "absent, failed, or corrupt preload must expose only the exact-scope bundle");
    Drain(callbacks);
    NSUInteger expectedImplicit =
        status == QONRemoteConfigV2ReadGuardPreloadStatusMissing ? 1 : 0;
    QON_CHECK(failSafeEvents == 1 && misuseEvents == 1 &&
        implicitEvents == expectedImplicit,
        "failed/corrupt preloads must not claim activation; missing may commit fallback activation");
  }

  GuardStorage *storage = [GuardStorage new]; storage.failWrites = YES;
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   PendingState());
  dispatch_queue_t callbacks = dispatch_queue_create("read.guard.disk-full", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger persistenceFailures = 0, diskMisuse = 0, diskImplicit = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventPreparedActivationPersistenceFailed) {
      persistenceFailures += 1;
    }
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate) diskMisuse += 1;
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) diskImplicit += 1;
  });
  QONRemoteConfigV2Scope *scope = Scope(@"user");
  QON_CHECK(PreloadOffMain(manager, scope) ==
      QONRemoteConfigV2ReadGuardPreloadStatusPersistenceFailed,
      "disk-full preparation must be an explicit preload failure");
  [manager setScope:scope];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"active"],
      "failed prepared activation must preserve the prior Active rather than Candidate");
  Drain(callbacks);
  QON_CHECK(persistenceFailures == 1 && diskMisuse == 1 && diskImplicit == 0,
      "persistence failure must be observable without a false implicit-activation success");
}

static void TestReadGuardCallbacksAreReentrantAndNeverRunUnderStateLock(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate", 2));
  dispatch_queue_t callbacks = dispatch_queue_create(
      "read.guard.reentrant-callbacks", DISPATCH_QUEUE_SERIAL);
  dispatch_semaphore_t telemetryFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t observerFinished = dispatch_semaphore_create(0);
  __block QONRemoteConfigV2Manager *manager = nil;
  __block BOOL telemetryReentered = NO;
  __block BOOL observerReentered = NO;
  manager = Manager(storage, preloader, QONRemoteConfigV2ReadGuardBuildModeRelease,
      callbacks, nil, ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) {
      telemetryReentered = manager.currentSnapshot != nil;
      dispatch_semaphore_signal(telemetryFinished);
    }
  });
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) {
    observerReentered = manager.currentSnapshot != nil;
    dispatch_semaphore_signal(observerFinished);
  }];
  QONRemoteConfigV2Scope *scope = Scope(@"user");
  PreloadOffMain(manager, scope);
  [manager setScope:scope];
  (void)manager.currentSnapshot;

  QON_CHECK(dispatch_semaphore_wait(telemetryFinished,
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0 && telemetryReentered,
      "telemetry callback must run outside the state lock and permit reentrant reads");
  QON_CHECK(dispatch_semaphore_wait(observerFinished,
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0 && observerReentered,
      "implicit activation observer must run outside the state lock and permit reentrant reads");

  GuardPreloader *debugPreloader = [GuardPreloader new];
  debugPreloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                        CandidateState(@"debug", 3));
  __block QONRemoteConfigV2Manager *debugManager = nil;
  __block BOOL assertionReentered = NO;
  debugManager = Manager([GuardStorage new], debugPreloader,
      QONRemoteConfigV2ReadGuardBuildModeDebug, callbacks, ^(__unused NSString *message) {
    assertionReentered = debugManager.lastFetchedSnapshot != nil;
  }, nil);
  PreloadOffMain(debugManager, scope);
  [debugManager setScope:scope];
  (void)debugManager.currentSnapshot;
  QON_CHECK(assertionReentered,
      "debug assertion hook must run outside the state lock and permit reentrant reads");
}

static void TestConcurrentFirstReadersClaimOneImplicitAttempt(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate", 2));
  dispatch_queue_t callbacks = dispatch_queue_create("read.guard.concurrent.events", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger misuse = 0, implicitActivations = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate) misuse += 1;
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) {
      implicitActivations += 1;
    }
  });
  QONRemoteConfigV2Scope *scope = Scope(@"user");
  PreloadOffMain(manager, scope);
  [manager setScope:scope];
  __block NSUInteger wrong = 0;
  dispatch_apply(64, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(__unused size_t index) {
    if (![manager.currentSnapshot.releaseUID isEqualToString:@"candidate"]) {
      @synchronized (manager) { wrong += 1; }
    }
  });
  Drain(callbacks);
  QON_CHECK(wrong == 0 && misuse == 1 && implicitActivations == 1,
      "concurrent first readers must observe one implicit attempt for the generation");
}

static void TestPreloadIsExactScopeBoundAndPreparedStateSurvivesRestart(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"private-a", 2));
  dispatch_queue_t callbacks = dispatch_queue_create("read.guard.scope", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2Manager *first = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil, nil);
  QONRemoteConfigV2Scope *userA = Scope(@"user-a");
  QONRemoteConfigV2Scope *userB = Scope(@"user-b");
  PreloadOffMain(first, userA);
  [first setScope:userB];
  QON_CHECK([first.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a preloaded user must never leak into a different current scope");
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"private-a", 2));
  PreloadOffMain(first, userA);
  [first setScope:userA];
  QON_CHECK([first.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a prior first-read opportunity must not be reset by a freshly preloaded scope");
  QON_CHECK([first activate] &&
      [first.currentSnapshot.releaseUID isEqualToString:@"private-a"],
      "explicit activation must expose only the freshly preloaded exact-scope candidate");

  QONRemoteConfigV2State *durable = nil;
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QON_CHECK([store loadStateForScope:userA state:&durable] == QONRemoteConfigV2StoreLoadStatusFound,
      "prepared activation must be durable before first read");
  GuardPreloader *restartPreloader = [GuardPreloader new];
  restartPreloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound, durable);
  QONRemoteConfigV2Manager *restart = Manager(storage, restartPreloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil, nil);
  PreloadOffMain(restart, userA);
  [restart setScope:userA];
  QON_CHECK([restart.currentSnapshot.releaseUID isEqualToString:@"private-a"],
      "restart must expose the same durably prepared Active snapshot");
}

static void TestOutOfOrderPreloadsCannotPublishASupersededSlot(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardAdversarialPreloader *preloader = [GuardAdversarialPreloader new];
  preloader.firstStarted = dispatch_semaphore_create(0);
  preloader.releaseFirst = dispatch_semaphore_create(0);
  preloader.waitForSupersedingToken = YES;
  preloader.resultA = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                    CandidateState(@"candidate-a", 2));
  preloader.resultB = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                    CandidateState(@"candidate-b", 3));
  dispatch_queue_t callbacks = dispatch_queue_create(
      "read.guard.out-of-order", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil, nil);
  preloader.manager = manager;
  QONRemoteConfigV2Scope *userA = Scope(@"user-a");
  QONRemoteConfigV2Scope *userB = Scope(@"user-b");
  dispatch_semaphore_t aFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t bFinished = dispatch_semaphore_create(0);
  __block QONRemoteConfigV2ReadGuardPreloadStatus aStatus =
      QONRemoteConfigV2ReadGuardPreloadStatusFound;
  __block QONRemoteConfigV2ReadGuardPreloadStatus bStatus =
      QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    aStatus = [manager preloadScopeForReadGuard:userA];
    dispatch_semaphore_signal(aFinished);
  });
  QON_CHECK(dispatch_semaphore_wait(preloader.firstStarted,
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
      "first adversarial preload must start");
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    bStatus = [manager preloadScopeForReadGuard:userB];
    dispatch_semaphore_signal(bFinished);
  });
  QON_CHECK(dispatch_semaphore_wait(aFinished,
      dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0 &&
      dispatch_semaphore_wait(bFinished,
      dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
      "adversarial preloads must finish without deadlock");
  QON_CHECK(aStatus == QONRemoteConfigV2ReadGuardPreloadStatusFailed &&
      bStatus == QONRemoteConfigV2ReadGuardPreloadStatusFound,
      "the superseded preload must fail while the newest issued preload wins");
  [manager setScope:userB];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"candidate-b"],
      "out-of-order completion must not overwrite the newest exact slot");
  [manager setScope:userA];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a superseded slot must never become eligible in a later scope generation");
}

static void TestScopeSelectionCancelsAnInFlightPreload(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardAdversarialPreloader *preloader = [GuardAdversarialPreloader new];
  preloader.firstStarted = dispatch_semaphore_create(0);
  preloader.releaseFirst = dispatch_semaphore_create(0);
  preloader.resultA = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                    CandidateState(@"late-a", 2));
  preloader.resultB = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusMissing, nil);
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease,
      dispatch_queue_create("read.guard.cancel", DISPATCH_QUEUE_SERIAL), nil, nil);
  preloader.manager = manager;
  QONRemoteConfigV2Scope *userA = Scope(@"user-a");
  dispatch_semaphore_t finished = dispatch_semaphore_create(0);
  __block QONRemoteConfigV2ReadGuardPreloadStatus status =
      QONRemoteConfigV2ReadGuardPreloadStatusFound;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    status = [manager preloadScopeForReadGuard:userA];
    dispatch_semaphore_signal(finished);
  });
  QON_CHECK(dispatch_semaphore_wait(preloader.firstStarted,
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
      "in-flight preload must reach the injected loading seam");
  [manager setScope:Scope(@"user-b")];
  dispatch_semaphore_signal(preloader.releaseFirst);
  QON_CHECK(dispatch_semaphore_wait(finished,
      dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0 &&
      status == QONRemoteConfigV2ReadGuardPreloadStatusFailed,
      "scope selection must cancel a preload that has not completed");
  [manager setScope:userA];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a preload completed after scope selection must not leak into a later generation");
}

static void TestScopeSelectionWaitsForAdmittedSaveAndFencesLateWrites(void) {
  GuardBlockingStorage *storage = [GuardBlockingStorage new];
  storage.blockNextWrite = YES;
  GuardPreloader *preloader = [GuardPreloader new];
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate-a", 2));
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease,
      dispatch_queue_create("read.guard.atomic-save", DISPATCH_QUEUE_SERIAL), nil, nil);
  QONRemoteConfigV2Scope *userA = Scope(@"user-a");
  QONRemoteConfigV2Scope *userB = Scope(@"user-b");
  dispatch_semaphore_t preloadFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t scopeReturned = dispatch_semaphore_create(0);
  __block QONRemoteConfigV2ReadGuardPreloadStatus status =
      QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  __block NSUInteger writesAtScopeReturn = NSNotFound;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    status = [manager preloadScopeForReadGuard:userA];
    dispatch_semaphore_signal(preloadFinished);
  });
  QON_CHECK(dispatch_semaphore_wait(storage.writeStarted,
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
      "preload must reach the blocking durable-save seam");
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager setScope:userB];
    writesAtScopeReturn = storage.writes;
    dispatch_semaphore_signal(scopeReturned);
  });

  QON_CHECK(dispatch_semaphore_wait(scopeReturned,
      dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0,
      "setScope must not return while an admitted preload save can still write");
  dispatch_semaphore_signal(storage.releaseWrite);
  QON_CHECK(dispatch_semaphore_wait(preloadFinished,
      dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0 &&
      dispatch_semaphore_wait(scopeReturned,
      dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
      "preload save and scope selection must finish without deadlock");
  QON_CHECK(status == QONRemoteConfigV2ReadGuardPreloadStatusFound,
      "an admitted save must publish before the later scope selection invalidates it");
  QON_CHECK(storage.writes == writesAtScopeReturn,
      "no preload write may occur after setScope returns");
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "the selected identity must never expose the saved prior-identity candidate");
}

static void TestImplicitActivationOpportunityIsOncePerSDKLifetime(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardPreloader *preloader = [GuardPreloader new];
  dispatch_queue_t callbacks = dispatch_queue_create(
      "read.guard.lifetime", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger implicit = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) implicit += 1;
  });
  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate-a", 2));
  PreloadOffMain(manager, Scope(@"user-a"));
  [manager setScope:Scope(@"user-a")];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"candidate-a"],
      "the first SDK-lifetime read may activate its durably prepared candidate");
  NSUInteger writesAfterFirstActivation = storage.writes;

  preloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                   CandidateState(@"candidate-b", 3));
  PreloadOffMain(manager, Scope(@"user-b"));
  QON_CHECK(storage.writes == writesAfterFirstActivation,
      "a later scope must not persist another implicit activation after lifetime use");
  [manager setScope:Scope(@"user-b")];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a later scope must require explicit activation after lifetime implicit use");
  Drain(callbacks);
  QON_CHECK(implicit == 1, "implicit activation telemetry must occur once per SDK lifetime");

  GuardStorage *explicitStorage = [GuardStorage new];
  GuardPreloader *explicitPreloader = [GuardPreloader new];
  __block NSUInteger explicitImplicit = 0;
  QONRemoteConfigV2Manager *explicitManager = Manager(explicitStorage, explicitPreloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) {
      explicitImplicit += 1;
    }
  });
  explicitPreloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                           CandidateState(@"explicit-a", 2));
  PreloadOffMain(explicitManager, Scope(@"explicit-a"));
  [explicitManager setScope:Scope(@"explicit-a")];
  QON_CHECK([explicitManager activate],
      "explicit activation must consume the SDK-lifetime implicit opportunity");
  NSUInteger writesAfterExplicit = explicitStorage.writes;

  explicitPreloader.result = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                           CandidateState(@"candidate-b", 3));
  PreloadOffMain(explicitManager, Scope(@"explicit-b"));
  QON_CHECK(explicitStorage.writes == writesAfterExplicit,
      "explicit activation must prevent later implicit-preparation writes");
  [explicitManager setScope:Scope(@"explicit-b")];
  QON_CHECK([explicitManager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a scope after explicit activation must not activate on first read");
  Drain(callbacks);
  QON_CHECK(explicitImplicit == 0,
      "explicit activation must prevent all implicit-activation telemetry");
}

static void TestReadDuringPreloadBindWindowCannotConsumeTargetOpportunity(void) {
  GuardStorage *storage = [GuardStorage new];
  GuardAdversarialPreloader *preloader = [GuardAdversarialPreloader new];
  preloader.firstStarted = dispatch_semaphore_create(0);
  preloader.releaseFirst = dispatch_semaphore_create(0);
  preloader.resultA = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusFound,
                                    CandidateState(@"candidate-a", 2));
  preloader.resultB = PreloadResult(QONRemoteConfigV2ReadGuardPreloadStatusMissing, nil);
  dispatch_queue_t callbacks = dispatch_queue_create(
      "read.guard.bind-window", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger implicit = 0;
  QONRemoteConfigV2Manager *manager = Manager(storage, preloader,
      QONRemoteConfigV2ReadGuardBuildModeRelease, callbacks, nil,
      ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    if (event == QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation) implicit += 1;
  });
  preloader.manager = manager;
  QONRemoteConfigV2Scope *userA = Scope(@"user-a");
  QONRemoteConfigV2Scope *userB = Scope(@"user-b");
  PreloadOffMain(manager, userB);
  [manager setScope:userB];

  dispatch_semaphore_t preloadFinished = dispatch_semaphore_create(0);
  __block QONRemoteConfigV2ReadGuardPreloadStatus status =
      QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    status = [manager preloadScopeForReadGuard:userA];
    dispatch_semaphore_signal(preloadFinished);
  });
  QON_CHECK(dispatch_semaphore_wait(preloader.firstStarted,
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
      "target preload must reach the bind-window seam");
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"bundle"],
      "a stale-scope read during target preload must stay on its safe fallback");
  dispatch_semaphore_signal(preloader.releaseFirst);
  QON_CHECK(dispatch_semaphore_wait(preloadFinished,
      dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0 &&
      status == QONRemoteConfigV2ReadGuardPreloadStatusFound,
      "target preload must finish after the stale-scope read");

  [manager setScope:userA];
  QON_CHECK([manager.currentSnapshot.releaseUID isEqualToString:@"candidate-a"],
      "a stale-scope read must not consume the target scope implicit opportunity");
  Drain(callbacks);
  QON_CHECK(implicit == 1,
      "the bound target scope must report exactly one implicit activation");
}

int main(void) {
  @autoreleasepool {
    TestReleaseFirstReadUsesDurablyPreparedCandidateOnlyOnce();
    TestFetchAfterPreloadRefreshesDurableFirstReadPreparation();
    TestPersistenceRecoveryRearmsAndImmediateDoesNotReportImplicit();
    TestDebugAssertionIsExactAndNeverImplicitlyActivates();
    TestUnavailablePreloadsAndPersistenceFailureStayOnPinnedBundle();
    TestConcurrentFirstReadersClaimOneImplicitAttempt();
    TestPreloadIsExactScopeBoundAndPreparedStateSurvivesRestart();
    TestReadGuardCallbacksAreReentrantAndNeverRunUnderStateLock();
    TestOutOfOrderPreloadsCannotPublishASupersededSlot();
    TestScopeSelectionCancelsAnInFlightPreload();
    TestScopeSelectionWaitsForAdmittedSaveAndFencesLateWrites();
    TestImplicitActivationOpportunityIsOncePerSDKLifetime();
    TestReadDuringPreloadBindWindowCannotConsumeTargetOpportunity();
  }
  fprintf(stdout, "QONRemoteConfigV2ReadGuardHarness: %lu/%lu passed\n",
          (unsigned long)(checks - failures), (unsigned long)checks);
  return failures == 0 ? 0 : 1;
}
