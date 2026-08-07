//
//  QONRemoteConfigController.m
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigController.h"
#import "QONRemoteConfigController+Protected.h"
#import "QONRemoteConfigSnapshot+Protected.h"

#import "QONRemoteConfigFallbackStore.h"
#import "QONRemoteConfigV2FetchPolicyStore.h"
#import "QONRemoteConfigV2GatewaySessionStore.h"
#import "QONRemoteConfigV2GatewayTransport.h"
#import "QONRemoteConfigV2Store.h"

// Defaults for the real engine only. They are new constants for a surface that
// is off by default and do not touch any shipping configuration.
static int64_t const kQONRemoteConfigMinimumFetchIntervalMilliseconds = 60 * 60 * 1000;
static int64_t const kQONRemoteConfigTransportTimeoutMilliseconds = 30 * 1000;
static int64_t const kQONRemoteConfigInitialBackoffMilliseconds = 2 * 1000;
static int64_t const kQONRemoteConfigMaximumBackoffMilliseconds = 60 * 60 * 1000;

#pragma mark - Engine building blocks

@interface QONRemoteConfigStorePreloader ()
@property (nonatomic, strong) QONRemoteConfigV2Store *store;
@end

@implementation QONRemoteConfigStorePreloader

- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store {
  if (!store) return nil;
  self = [super init];
  if (self) {
    _store = store;
  }
  return self;
}

- (QONRemoteConfigV2ReadGuardPreloadResult *)preloadResultForScope:(QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2State *state = nil;
  QONRemoteConfigV2ReadGuardPreloadStatus status =
      QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  switch ([self.store loadStateForScope:scope state:&state]) {
    case QONRemoteConfigV2StoreLoadStatusFound:
      status = state ? QONRemoteConfigV2ReadGuardPreloadStatusFound
                     : QONRemoteConfigV2ReadGuardPreloadStatusCorrupt;
      break;
    case QONRemoteConfigV2StoreLoadStatusMissing:
      status = QONRemoteConfigV2ReadGuardPreloadStatusMissing;
      state = nil;
      break;
    case QONRemoteConfigV2StoreLoadStatusFailed:
      status = QONRemoteConfigV2ReadGuardPreloadStatusFailed;
      state = nil;
      break;
  }
  QONRemoteConfigV2ReadGuardPreloadResult *result = [[QONRemoteConfigV2ReadGuardPreloadResult alloc]
      initWithStatus:status
               state:status == QONRemoteConfigV2ReadGuardPreloadStatusFound ? state : nil];
  return result ?: [[QONRemoteConfigV2ReadGuardPreloadResult alloc]
      initWithStatus:QONRemoteConfigV2ReadGuardPreloadStatusFailed state:nil];
}

@end

@implementation QONRemoteConfigSystemClock

- (int64_t)nowMilliseconds {
  return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000.0);
}

@end

@implementation QONRemoteConfigSystemRandom

- (double)nextUnitInterval {
  return (double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX;
}

@end

@interface QONRemoteConfigDispatchTask : NSObject <QONRemoteConfigV2FetchScheduledTask>
@property (nonatomic, strong, nullable) dispatch_source_t timer;
@end

@implementation QONRemoteConfigDispatchTask

- (void)cancel {
  dispatch_source_t timer = nil;
  @synchronized (self) {
    timer = self.timer;
    self.timer = nil;
  }
  if (timer) dispatch_source_cancel(timer);
}

@end

@interface QONRemoteConfigDispatchScheduler ()
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation QONRemoteConfigDispatchScheduler

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
  if (!queue) return nil;
  self = [super init];
  if (self) {
    _queue = queue;
  }
  return self;
}

- (id<QONRemoteConfigV2FetchScheduledTask>)scheduleAfterMilliseconds:(int64_t)delay
                                                              action:(dispatch_block_t)action {
  QONRemoteConfigDispatchTask *task = [QONRemoteConfigDispatchTask new];
  if (!action) return task;
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
  task.timer = timer;
  int64_t safeDelay = MAX(delay, 0);
  dispatch_source_set_timer(timer,
      dispatch_time(DISPATCH_TIME_NOW, safeDelay * (int64_t)NSEC_PER_MSEC),
      DISPATCH_TIME_FOREVER, (uint64_t)(10 * NSEC_PER_MSEC));
  dispatch_source_set_event_handler(timer, ^{
    // One-shot: cancel before running so a fired task can never fire twice.
    [task cancel];
    action();
  });
  dispatch_resume(timer);
  return task;
}

@end

#pragma mark - One public fetch call

/** Terminal ownership of a single public fetch call. */
@interface QONRemoteConfigCall : NSObject
@property (nonatomic, copy) QONRemoteConfigFetchCompletion completion;
@property (nonatomic, assign) BOOL shouldActivate;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduledTask> deadlineTask;
@property (nonatomic, assign) BOOL claimed;
@end

@implementation QONRemoteConfigCall

/** Returns YES exactly once per call, for whichever of the two paths wins. */
- (BOOL)claim {
  @synchronized (self) {
    if (self.claimed) return NO;
    self.claimed = YES;
    return YES;
  }
}

- (id<QONRemoteConfigV2FetchScheduledTask>)takeDeadlineTask {
  @synchronized (self) {
    id<QONRemoteConfigV2FetchScheduledTask> task = self.deadlineTask;
    self.deadlineTask = nil;
    return task;
  }
}

- (void)setDeadlineTaskSafely:(id<QONRemoteConfigV2FetchScheduledTask>)task {
  BOOL alreadyClaimed = NO;
  @synchronized (self) {
    alreadyClaimed = self.claimed;
    if (!alreadyClaimed) self.deadlineTask = task;
  }
  if (alreadyClaimed) [task cancel];
}

@end

#pragma mark - Controller

@interface QONRemoteConfigController ()
@property (nonatomic, strong, nullable) QONRemoteConfigFallbackStore *fallbackStore;
@property (nonatomic, strong) dispatch_queue_t callbackExecutor;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Manager *manager;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchCoordinator *coordinator;
@property (nonatomic, copy, nullable) NSString *projectKey;
@property (nonatomic, copy, nullable) NSString *environment;
@property (nonatomic, copy, nullable) QONRemoteConfigBindingProvider bindingProvider;
@property (nonatomic, copy, nullable) QONRemoteConfigScopeSink scopeSink;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduler> scheduler;
@property (nonatomic, strong, nullable) dispatch_queue_t identityQueue;
/** Serializes scope transitions against each other only, never against reads. */
@property (nonatomic, strong) NSObject *identityLock;
@property (nonatomic, assign) NSUInteger identityEpoch;
@property (nonatomic, copy, nullable) NSString *boundCanonicalUserID;
@property (nonatomic, assign) BOOL hasBoundIdentity;
@end

@implementation QONRemoteConfigController

- (instancetype)initWithFallbackStore:(QONRemoteConfigFallbackStore *)fallbackStore
                     callbackExecutor:(dispatch_queue_t)callbackExecutor {
  if (!callbackExecutor) return nil;
  self = [super init];
  if (self) {
    _fallbackStore = fallbackStore;
    _callbackExecutor = callbackExecutor;
    _identityLock = [NSObject new];
  }
  return self;
}

#pragma mark - Engine installation

- (BOOL)installEngineWithManager:(QONRemoteConfigV2Manager *)manager
                     coordinator:(QONRemoteConfigV2FetchCoordinator *)coordinator
                      projectKey:(NSString *)projectKey
                     environment:(NSString *)environment
                 bindingProvider:(QONRemoteConfigBindingProvider)bindingProvider
                       scopeSink:(QONRemoteConfigScopeSink)scopeSink
                       scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                   identityQueue:(dispatch_queue_t)identityQueue {
  if (!manager || !coordinator || !projectKey.length || !environment.length ||
      !bindingProvider || !scheduler || !identityQueue) {
    return NO;
  }
  @synchronized (self) {
    if (self.manager) return NO;
    self.manager = manager;
    self.coordinator = coordinator;
    self.projectKey = projectKey;
    self.environment = environment;
    self.bindingProvider = bindingProvider;
    self.scopeSink = scopeSink;
    self.scheduler = scheduler;
    self.identityQueue = identityQueue;
  }
  return YES;
}

- (BOOL)configureWithBaseURL:(NSURL *)baseURL
                projectToken:(NSString *)projectToken
                  projectKey:(NSString *)projectKey
                 environment:(NSString *)environment
             canonicalUserID:(NSString *)canonicalUserID
                localStorage:(id<QNLocalStorage>)localStorage
       clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider
             bindingProvider:(QONRemoteConfigBindingProvider)bindingProvider {
  if (!baseURL || !projectToken.length || !localStorage || !clientContextProvider ||
      !bindingProvider) {
    return NO;
  }
  QONRemoteConfigV2Store *store = [QONRemoteConfigV2Store applicationSupportStore]
      ?: [[QONRemoteConfigV2Store alloc] initWithLocalStorage:localStorage];
  QONRemoteConfigStorePreloader *preloader =
      [[QONRemoteConfigStorePreloader alloc] initWithStore:store];
  QONRemoteConfigV2Release *fallbackRelease = self.fallbackStore.remoteConfigV2FallbackRelease;
#ifdef DEBUG
  QONRemoteConfigV2ReadGuardBuildMode buildMode = QONRemoteConfigV2ReadGuardBuildModeDebug;
#else
  QONRemoteConfigV2ReadGuardBuildMode buildMode = QONRemoteConfigV2ReadGuardBuildModeRelease;
#endif
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:store
      fallbackRelease:fallbackRelease
      fallbackProjectKey:fallbackRelease ? projectKey : nil
      fallbackEnvironment:fallbackRelease ? environment : nil
      envelopeDecoder:[QONRemoteConfigV2EnvelopeParser new]
      callbackExecutor:self.callbackExecutor
      readGuardBuildMode:buildMode
      assertionHandler:^(NSString *message) { NSCAssert(NO, @"%@", message); }
      telemetryHandler:nil
      scopePreloader:preloader];
  if (!manager) return NO;

  dispatch_queue_t schedulerQueue = dispatch_queue_create(
      "io.qonversion.remote-config-scheduler", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigDispatchScheduler *scheduler =
      [[QONRemoteConfigDispatchScheduler alloc] initWithQueue:schedulerQueue];
  QONRemoteConfigSystemClock *clock = [QONRemoteConfigSystemClock new];
  QONRemoteConfigV2GatewaySessionStore *sessionStore =
      [[QONRemoteConfigV2GatewaySessionStore alloc] initWithLocalStorage:localStorage];
  QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
      initWithBaseURL:baseURL
      projectToken:projectToken
      httpExecutor:[[QONRemoteConfigV2URLSessionHTTPExecutor alloc]
          initWithSession:NSURLSession.sharedSession]
      sessionStore:sessionStore
      clientContextProvider:clientContextProvider
      clock:clock
      failureObserver:nil];
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:kQONRemoteConfigMinimumFetchIntervalMilliseconds
      timeoutMilliseconds:@(kQONRemoteConfigTransportTimeoutMilliseconds)
      initialBackoffMilliseconds:kQONRemoteConfigInitialBackoffMilliseconds
      maximumBackoffMilliseconds:kQONRemoteConfigMaximumBackoffMilliseconds];
  QONRemoteConfigV2FetchPolicyStore *policyStore =
      [[QONRemoteConfigV2FetchPolicyStore alloc] initWithLocalStorage:localStorage];
  if (!scheduler || !sessionStore || !transport || !policy || !policyStore) return NO;
  QONRemoteConfigV2FetchCoordinator *coordinator = [[QONRemoteConfigV2FetchCoordinator alloc]
      initWithCore:manager transport:transport policyStore:policyStore clock:clock
      random:[QONRemoteConfigSystemRandom new] scheduler:scheduler policy:policy];
  if (!coordinator) return NO;

  __weak QONRemoteConfigV2GatewayTransport *weakTransport = transport;
  BOOL installed = [self installEngineWithManager:manager
                                      coordinator:coordinator
                                       projectKey:projectKey
                                      environment:environment
                                  bindingProvider:bindingProvider
                                        scopeSink:^(QONRemoteConfigV2Scope *scope) {
                                          [weakTransport updateScope:scope];
                                        }
                                        scheduler:scheduler
                                    identityQueue:dispatch_queue_create(
                                        "io.qonversion.remote-config-identity",
                                        DISPATCH_QUEUE_SERIAL)];
  if (!installed) return NO;
  [self switchToCanonicalUserID:canonicalUserID
                         change:QONRemoteConfigControllerIdentityChangeBuild];
  return YES;
}

- (BOOL)isConfigured {
  @synchronized (self) {
    return self.manager != nil;
  }
}

#pragma mark - Identity

- (void)switchToCanonicalUserID:(NSString *)canonicalUserID
                         change:(QONRemoteConfigControllerIdentityChange)change {
  QONRemoteConfigV2Manager *manager = nil;
  QONRemoteConfigV2FetchCoordinator *coordinator = nil;
  QONRemoteConfigBindingProvider bindingProvider = nil;
  QONRemoteConfigScopeSink scopeSink = nil;
  dispatch_queue_t identityQueue = nil;
  NSString *projectKey = nil;
  NSString *environment = nil;
  @synchronized (self) {
    manager = self.manager;
    coordinator = self.coordinator;
    bindingProvider = self.bindingProvider;
    scopeSink = self.scopeSink;
    identityQueue = self.identityQueue;
    projectKey = self.projectKey;
    environment = self.environment;
  }
  if (!manager || !coordinator) return;

  QONRemoteConfigV2Scope *scope = canonicalUserID.length > 0
      ? [[QONRemoteConfigV2Scope alloc] initWithProjectKey:projectKey
                                              environment:environment
                                          canonicalUserID:canonicalUserID]
      : nil;

  NSUInteger epoch = 0;
  @synchronized (self.identityLock) {
    BOOL sameIdentity = self.hasBoundIdentity &&
        ((self.boundCanonicalUserID == nil && scope == nil) ||
         [self.boundCanonicalUserID isEqualToString:scope.canonicalUserID]);
    if (sameIdentity) return;
    self.identityEpoch += 1;
    epoch = self.identityEpoch;
    self.boundCanonicalUserID = scope.canonicalUserID;
    self.hasBoundIdentity = YES;
    // Unbind first and synchronously: after this returns, no read can observe
    // the retired identity's configuration, whatever the rebind below does. A
    // rebind queued by an older switch is fenced out by the epoch.
    [coordinator transitionToBinding:nil];
    if (scopeSink) scopeSink(nil);
  }
  if (!scope) return;

  dispatch_async(identityQueue, ^{
    @synchronized (self.identityLock) {
      if (self.identityEpoch != epoch) return;
    }
    // The read guard requires all persistent work to finish off the main queue
    // before the scope is bound.
    [manager preloadScopeForReadGuard:scope];
    QONRemoteConfigV2FetchBinding *binding = nil;
    @try {
      binding = bindingProvider(scope);
    } @catch (__unused NSException *exception) {}
    QONRemoteConfigV2FetchForceReason reason =
        change == QONRemoteConfigControllerIdentityChangeLogout
            ? QONRemoteConfigV2FetchForceReasonLogout
            : (change == QONRemoteConfigControllerIdentityChangeIdentify
                   ? QONRemoteConfigV2FetchForceReasonIdentify
                   : QONRemoteConfigV2FetchForceReasonBuild);
    @synchronized (self.identityLock) {
      // Publishing under the same lock as the unbind above keeps the two
      // orderings the only possible ones: either this scope is already stale,
      // or a newer switch retires it afterwards.
      if (self.identityEpoch != epoch) return;
      if (scopeSink) scopeSink(scope);
      if (!binding || ![binding.scope isEqual:scope]) {
        [manager setScope:scope];
        return;
      }
      [coordinator transitionToBinding:binding];
    }
    [coordinator fetchWithForceReason:reason
                           completion:^(__unused QONRemoteConfigV2FetchResult *result) {}];
  });
}

#pragma mark - Reads

- (QONRemoteConfigSnapshot *)fallbackOnlySnapshot {
  return [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:nil
             previousRelease:nil
             fallbackRelease:self.fallbackStore.remoteConfigV2FallbackRelease];
}

- (QONRemoteConfigSnapshot *)current {
  QONRemoteConfigV2Manager *manager = nil;
  @synchronized (self) {
    manager = self.manager;
  }
  return manager ? manager.currentSnapshot : [self fallbackOnlySnapshot];
}

- (QONRemoteConfigValue *)valueForKey:(NSString *)key
                              decoder:(QONRemoteConfigValueDecoder)decoder {
  if (!key || !decoder) return nil;
  return [self.current valueForKey:key decoder:decoder];
}

- (QONRemoteConfigValue *)rawValueForKey:(NSString *)key {
  if (!key) return nil;
  return [self.current rawValueForKey:key];
}

- (id)bundledFallbackValueForKey:(NSString *)key {
  return [self.fallbackStore valueForContextKey:key];
}

- (NSData *)bundledFallbackRawValueForKey:(NSString *)key {
  return [self.fallbackStore rawValueForContextKey:key];
}

#pragma mark - Activation

- (BOOL)activate {
  QONRemoteConfigV2Manager *manager = nil;
  @synchronized (self) {
    manager = self.manager;
  }
  return manager ? [manager activate] : NO;
}

#pragma mark - Fetching

- (void)fetchWithCompletion:(QONRemoteConfigFetchCompletion)completion {
  [self fetchWithTimeout:0 completion:completion];
}

- (void)fetchAndActivateWithCompletion:(QONRemoteConfigFetchCompletion)completion {
  [self fetchAndActivateWithTimeout:0 completion:completion];
}

- (void)fetchWithTimeout:(NSTimeInterval)timeout
              completion:(QONRemoteConfigFetchCompletion)completion {
  [self startFetchWithTimeout:timeout activate:NO completion:completion];
}

- (void)fetchAndActivateWithTimeout:(NSTimeInterval)timeout
                         completion:(QONRemoteConfigFetchCompletion)completion {
  [self startFetchWithTimeout:timeout activate:YES completion:completion];
}

- (QONRemoteConfigFetchStatus)statusForResultKind:(QONRemoteConfigV2FetchResultKind)kind {
  switch (kind) {
    case QONRemoteConfigV2FetchResultKindFetched:
      return QONRemoteConfigFetchStatusFetched;
    case QONRemoteConfigV2FetchResultKindNotModified:
      return QONRemoteConfigFetchStatusNotModified;
    case QONRemoteConfigV2FetchResultKindMinimumInterval:
    case QONRemoteConfigV2FetchResultKindBackoff:
      return QONRemoteConfigFetchStatusThrottled;
    case QONRemoteConfigV2FetchResultKindTimedOut:
      return QONRemoteConfigFetchStatusTimedOut;
    case QONRemoteConfigV2FetchResultKindFailed:
    case QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed:
    case QONRemoteConfigV2FetchResultKindInvalidNotModified:
    case QONRemoteConfigV2FetchResultKindSuperseded:
      return QONRemoteConfigFetchStatusFailed;
  }
  return QONRemoteConfigFetchStatusFailed;
}

- (void)deliverStatus:(QONRemoteConfigFetchStatus)status
             snapshot:(QONRemoteConfigSnapshot *)snapshot
              changed:(BOOL)changed
 hasPendingActivation:(BOOL)hasPendingActivation
              forCall:(QONRemoteConfigCall *)call {
  QONRemoteConfigFetchCompletion completion = call.completion;
  QONRemoteConfigFetchResult *result = [[QONRemoteConfigFetchResult alloc]
      initWithStatus:status
            snapshot:snapshot ?: [self fallbackOnlySnapshot]
             changed:changed
hasPendingActivation:hasPendingActivation];
  if (!completion || !result) return;
  dispatch_async(self.callbackExecutor, ^{
    @try {
      completion(result);
    } @catch (__unused NSException *exception) {}
  });
}

- (void)startFetchWithTimeout:(NSTimeInterval)timeout
                     activate:(BOOL)shouldActivate
                   completion:(QONRemoteConfigFetchCompletion)completion {
  if (!completion) return;
  QONRemoteConfigV2Manager *manager = nil;
  QONRemoteConfigV2FetchCoordinator *coordinator = nil;
  id<QONRemoteConfigV2FetchScheduler> scheduler = nil;
  @synchronized (self) {
    manager = self.manager;
    coordinator = self.coordinator;
    scheduler = self.scheduler;
  }
  QONRemoteConfigCall *call = [QONRemoteConfigCall new];
  call.completion = completion;
  call.shouldActivate = shouldActivate;

  if (!manager || !coordinator) {
    if ([call claim]) {
      [self deliverStatus:QONRemoteConfigFetchStatusUnavailable
                 snapshot:[self fallbackOnlySnapshot]
                  changed:NO
     hasPendingActivation:NO
                  forCall:call];
    }
    return;
  }

  if (timeout > 0 && scheduler) {
    int64_t deadline = (int64_t)(timeout * 1000.0);
    __weak typeof(self) weakSelf = self;
    id<QONRemoteConfigV2FetchScheduledTask> task = nil;
    @try {
      task = [scheduler scheduleAfterMilliseconds:deadline action:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || ![call claim]) return;
        // The request itself is intentionally left running: only the wait ends.
        // The snapshot is read unguarded for the same reason as below — the SDK
        // is the reader here, and a slow network must not raise the app's
        // read-before-activate assertion or silently spend its one implicit
        // activation.
        [strongSelf deliverStatus:QONRemoteConfigFetchStatusTimedOut
                         snapshot:manager.unguardedSnapshot
                          changed:NO
             hasPendingActivation:NO
                          forCall:call];
      }];
    } @catch (__unused NSException *exception) {
      task = nil;
    }
    [call setDeadlineTaskSafely:task];
  }

  __weak typeof(self) weakSelf = self;
  [coordinator fetchWithForceReason:QONRemoteConfigV2FetchForceReasonNone
                         completion:^(QONRemoteConfigV2FetchResult *result) {
    typeof(self) strongSelf = weakSelf;
    if (!strongSelf) return;
    if (![call claim]) return;
    [[call takeDeadlineTask] cancel];

    BOOL changed = result.transitionStatus == QONRemoteConfigV2TransitionStatusActivated;
    BOOL pending = result.transitionStatus == QONRemoteConfigV2TransitionStatusAccepted;
    if (call.shouldActivate) {
      if ([manager activate]) changed = YES;
      pending = NO;
    }
    // A completed fetch is the SDK reading, not the app: it must not consume the
    // app's one read-before-activate opportunity.
    [strongSelf deliverStatus:[strongSelf statusForResultKind:result.kind]
                     snapshot:manager.unguardedSnapshot
                      changed:changed
         hasPendingActivation:pending
                      forCall:call];
  }];
}

#pragma mark - Updates

- (id)subscribeOnConfigUpdate:(QONRemoteConfigUpdateHandler)handler {
  if (!handler) return nil;
  QONRemoteConfigV2Manager *manager = nil;
  @synchronized (self) {
    manager = self.manager;
  }
  return [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    handler(update);
  }];
}

- (void)unsubscribe:(id)token {
  if (!token) return;
  QONRemoteConfigV2Manager *manager = nil;
  @synchronized (self) {
    manager = self.manager;
  }
  [manager removeUpdateObserver:token];
}

@end
