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
#import "QONRemoteConfigV2ProjectIdentityStore.h"
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

/** Opaque subscription token that outlives the dormant-to-configured boundary. */
@interface QONRemoteConfigSubscription : NSObject
@property (nonatomic, copy) QONRemoteConfigUpdateHandler handler;
@property (nonatomic, strong, nullable) id observerToken;
@end

@implementation QONRemoteConfigSubscription
@end

@interface QONRemoteConfigController ()
@property (nonatomic, strong, nullable) QONRemoteConfigFallbackStore *fallbackStore;
@property (nonatomic, strong) dispatch_queue_t callbackExecutor;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Manager *manager;
@property (nonatomic, strong, nullable) QONRemoteConfigV2FetchCoordinator *coordinator;
@property (nonatomic, copy, nullable) NSString *projectKey;
@property (nonatomic, copy, nullable) NSString *environment;
@property (nonatomic, copy, nullable) QONRemoteConfigScopeSink scopeSink;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduler> scheduler;
@property (nonatomic, strong, nullable) dispatch_queue_t identityQueue;
/** Serializes scope transitions against each other only, never against reads. */
@property (nonatomic, strong) NSObject *identityLock;
@property (nonatomic, assign) NSUInteger identityEpoch;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigSubscription *> *subscriptions;
@property (nonatomic, copy, nullable) NSString *boundCanonicalUserID;
@property (nonatomic, assign) BOOL hasBoundIdentity;
/**
 Guards the ack queue and the noted-activation cache below.

 Always taken inside `identityLock`, never around it: an identity transition
 rebinds the ack queue while it holds the identity lock, and a plain read must
 never be able to acquire the two in the other order.
 */
@property (nonatomic, strong) NSObject *ackLock;
@property (nonatomic, strong, nullable) QONRemoteConfigV2ActivationAckSender *ackSender;
/**
 The telemetry queue shares `ackLock` and `ackScope` with the ack queue.

 They are the same kind of thing — out-of-band signals bound to the identity the
 transport currently addresses — and giving them one lock is what keeps a scope
 transition from ever binding them to two different identities.
 */
@property (nonatomic, strong, nullable) QONRemoteConfigV2TelemetrySender *telemetrySender;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *ackScope;
/**
 The (scope, release) already handed to the ack queue, so an ordinary `current`
 read costs one comparison instead of a queue hop. It is a cache of the sender's
 own idempotency, never a substitute for it: the sender is the only thing that
 decides whether an ack is actually owed.

 The scope is part of it precisely because the cache is written from the
 caller's thread: a read that started before an identity change can land after
 it, and a bare release number would then suppress the new identity's ack for
 the same release number.
 */
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *notedActivationScope;
@property (nonatomic, assign) NSInteger notedActivationReleaseNumber;
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
    _ackLock = [NSObject new];
    _subscriptions = [NSMutableArray new];
    // No engine, so no interval. Not 0, which is a real "never throttle".
    _installedMinimumFetchIntervalMilliseconds = -1;
  }
  return self;
}

#pragma mark - Engine installation

- (BOOL)installEngineWithManager:(QONRemoteConfigV2Manager *)manager
                     coordinator:(QONRemoteConfigV2FetchCoordinator *)coordinator
                      projectKey:(NSString *)projectKey
                     environment:(NSString *)environment
                       scopeSink:(QONRemoteConfigScopeSink)scopeSink
                       scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                   identityQueue:(dispatch_queue_t)identityQueue {
  if (!manager || !coordinator || !projectKey.length || !environment.length ||
      !scheduler || !identityQueue) {
    return NO;
  }
  NSArray<QONRemoteConfigSubscription *> *pending = nil;
  @synchronized (self) {
    if (self.manager) return NO;
    self.manager = manager;
    self.coordinator = coordinator;
    self.projectKey = projectKey;
    self.environment = environment;
    self.scopeSink = scopeSink;
    self.scheduler = scheduler;
    self.identityQueue = identityQueue;
    pending = [self.subscriptions copy];
  }
  // Replay handlers registered while the surface was still dormant, in the
  // order the app subscribed.
  for (QONRemoteConfigSubscription *subscription in pending) {
    id observerToken = [manager addUpdateObserver:subscription.handler];
    @synchronized (self) {
      if ([self.subscriptions containsObject:subscription]) {
        subscription.observerToken = observerToken;
        continue;
      }
    }
    [manager removeUpdateObserver:observerToken];
  }
  return YES;
}

- (BOOL)installActivationAckSender:(QONRemoteConfigV2ActivationAckSender *)ackSender {
  if (!ackSender) return NO;
  @synchronized (self.ackLock) {
    if (self.ackSender) return NO;
    self.ackSender = ackSender;
  }
  return YES;
}

- (BOOL)installTelemetrySender:(QONRemoteConfigV2TelemetrySender *)telemetrySender {
  if (!telemetrySender) return NO;
  @synchronized (self.ackLock) {
    if (self.telemetrySender) return NO;
    self.telemetrySender = telemetrySender;
  }
  return YES;
}

#pragma mark - Telemetry taps

- (QONRemoteConfigV2ReadGuardTelemetryHandler)telemetryReadGuardHandler {
  __weak typeof(self) weakSelf = self;
  return ^(QONRemoteConfigV2ReadGuardTelemetryEvent event) {
    [weakSelf recordReadGuardTelemetryEvent:event];
  };
}

- (QONRemoteConfigV2DecodeFailureTelemetryHandler)telemetryDecodeFailureHandler {
  __weak typeof(self) weakSelf = self;
  return ^(NSString *logicalKey, NSInteger releaseNumber) {
    [weakSelf recordTelemetryKind:QONRemoteConfigV2TelemetryKindDecodeFailure
                       logicalKey:logicalKey
                    releaseNumber:(int64_t)releaseNumber];
  };
}

- (QONRemoteConfigV2TransportFailureObserver)telemetryTransportFailureObserver {
  __weak typeof(self) weakSelf = self;
  return ^(QONRemoteConfigV2TransportFailureKind kind, __unused NSNumber *statusCode) {
    // Only the two "the server said something this SDK cannot parse" kinds are
    // reported. Every other kind is a network or authorization fact the gateway
    // already knows first-hand, and reporting it back would be noise.
    //
    // Both map to snapshot_malformed, which the contract defines as any gateway
    // response envelope this client could not parse — the bootstrap envelope
    // included. A separate kind would split one server-side defect across two
    // dashboard rows for no operational gain.
    if (kind != QONRemoteConfigV2TransportFailureKindSnapshotMalformed &&
        kind != QONRemoteConfigV2TransportFailureKindBootstrapMalformed) {
      return;
    }
    [weakSelf recordTelemetryKind:QONRemoteConfigV2TelemetryKindSnapshotMalformed
                       logicalKey:nil
                    releaseNumber:0];
  };
}

/** The SDK-internal read-guard vocabulary, translated to the wire's closed enum. */
- (void)recordReadGuardTelemetryEvent:(QONRemoteConfigV2ReadGuardTelemetryEvent)event {
  QONRemoteConfigV2TelemetryKind kind;
  switch (event) {
    case QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate:
      kind = QONRemoteConfigV2TelemetryKindReadBeforeActivate;
      break;
    case QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation:
      kind = QONRemoteConfigV2TelemetryKindImplicitActivation;
      break;
    // Deliberately NOT reported. An absent preload is what every fresh install
    // looks like before its first fetch — the normal state, not a fault — so
    // reporting it would make preload_failed fire once for every new user and
    // bury the genuine failures underneath. Only a preload that tried and could
    // not is a failure.
    case QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent:
      return;
    case QONRemoteConfigV2ReadGuardTelemetryEventPreloadFailed:
      kind = QONRemoteConfigV2TelemetryKindPreloadFailed;
      break;
    case QONRemoteConfigV2ReadGuardTelemetryEventPreloadCorrupt:
      kind = QONRemoteConfigV2TelemetryKindPreloadCorrupt;
      break;
    case QONRemoteConfigV2ReadGuardTelemetryEventPreparedActivationPersistenceFailed:
      kind = QONRemoteConfigV2TelemetryKindActivationPersistenceFailed;
      break;
    default:
      return;
  }
  // The read-guard kinds name no key and no release: the release number would
  // have to be read back out of the manager, and this handler runs on the read
  // path, where re-entering the manager is exactly what it may not do. The
  // contract spells that "unknown" as 0.
  [self recordTelemetryKind:kind logicalKey:nil releaseNumber:0];
}

/**
 Hands one observation to the telemetry queue.

 Every caller is a path the app is waiting on, so this must stay a lookup and a
 hand-off. The sender's own queue is where the event is coalesced, persisted and
 sent, and nothing here can fail in a way the caller could observe.
 */
- (void)recordTelemetryKind:(QONRemoteConfigV2TelemetryKind)kind
                 logicalKey:(nullable NSString *)logicalKey
              releaseNumber:(int64_t)releaseNumber {
  QONRemoteConfigV2TelemetrySender *sender = nil;
  @synchronized (self.ackLock) {
    sender = self.telemetrySender;
  }
  [sender recordKind:kind logicalKey:logicalKey releaseNumber:releaseNumber];
}

/** A fetch just succeeded, so the buffered telemetry has a reachable network. */
- (void)noteTelemetryFlushOpportunity {
  QONRemoteConfigV2TelemetrySender *sender = nil;
  @synchronized (self.ackLock) {
    sender = self.telemetrySender;
  }
  [sender noteSuccessfulFetch];
}

- (BOOL)configureWithBaseURL:(NSURL *)baseURL
                projectToken:(NSString *)projectToken
                  projectKey:(NSString *)projectKey
                 environment:(NSString *)environment
             canonicalUserID:(NSString *)canonicalUserID
          readGuardBuildMode:(QONRemoteConfigV2ReadGuardBuildMode)buildMode
                localStorage:(id<QNLocalStorage>)localStorage
       clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider {
  return [self configureWithBaseURL:baseURL
                       projectToken:projectToken
                         projectKey:projectKey
                        environment:environment
                    canonicalUserID:canonicalUserID
                 readGuardBuildMode:buildMode
                       localStorage:localStorage
              clientContextProvider:clientContextProvider
   minimumFetchIntervalMilliseconds:nil];
}

- (BOOL)configureWithBaseURL:(NSURL *)baseURL
                projectToken:(NSString *)projectToken
                  projectKey:(NSString *)projectKey
                 environment:(NSString *)environment
             canonicalUserID:(NSString *)canonicalUserID
          readGuardBuildMode:(QONRemoteConfigV2ReadGuardBuildMode)buildMode
                localStorage:(id<QNLocalStorage>)localStorage
       clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider
minimumFetchIntervalMilliseconds:(NSNumber *)minimumFetchIntervalMilliseconds {
  if (!baseURL || !projectToken.length || !localStorage || !clientContextProvider) {
    return NO;
  }
  // The SDK's constant is the default, not a floor and not a ceiling: a stated
  // interval replaces it outright, including a stated 0.
  int64_t minimumFetchInterval = minimumFetchIntervalMilliseconds
      ? minimumFetchIntervalMilliseconds.longLongValue
      : kQONRemoteConfigMinimumFetchIntervalMilliseconds;
  // The policy refuses a negative interval too, by returning nil from its own
  // initializer. Refusing it here as well keeps the reason legible: the assembly
  // did not fail to build, it was asked for something that is not an interval.
  if (minimumFetchInterval < 0) return NO;
  QONRemoteConfigV2Store *store = [QONRemoteConfigV2Store applicationSupportStore]
      ?: [[QONRemoteConfigV2Store alloc] initWithLocalStorage:localStorage];
  QONRemoteConfigStorePreloader *preloader =
      [[QONRemoteConfigStorePreloader alloc] initWithStore:store];
  QONRemoteConfigV2Release *fallbackRelease = self.fallbackStore.remoteConfigV2FallbackRelease;
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:store
      fallbackRelease:fallbackRelease
      fallbackProjectKey:fallbackRelease ? projectKey : nil
      fallbackEnvironment:fallbackRelease ? environment : nil
      envelopeDecoder:[QONRemoteConfigV2EnvelopeParser new]
      callbackExecutor:self.callbackExecutor
      readGuardBuildMode:buildMode
      assertionHandler:^(NSString *message) { NSCAssert(NO, @"%@", message); }
      telemetryHandler:[self telemetryReadGuardHandler]
      scopePreloader:preloader];
  if (!manager) return NO;
  // Attached before anything can read: a snapshot handed out without it would
  // silently swallow the one decode failure the dashboard exists to show.
  manager.decodeFailureTelemetryHandler = [self telemetryDecodeFailureHandler];

  dispatch_queue_t schedulerQueue = dispatch_queue_create(
      "io.qonversion.remote-config-scheduler", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigDispatchScheduler *scheduler =
      [[QONRemoteConfigDispatchScheduler alloc] initWithQueue:schedulerQueue];
  QONRemoteConfigSystemClock *clock = [QONRemoteConfigSystemClock new];
  QONRemoteConfigV2GatewaySessionStore *sessionStore =
      [[QONRemoteConfigV2GatewaySessionStore alloc] initWithLocalStorage:localStorage];
  QONRemoteConfigV2ProjectIdentityStore *projectIdentityStore =
      [[QONRemoteConfigV2ProjectIdentityStore alloc] initWithLocalStorage:localStorage
                                                                  baseURL:baseURL
                                                             projectToken:projectToken];
  QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
      initWithBaseURL:baseURL
      projectToken:projectToken
      httpExecutor:[[QONRemoteConfigV2URLSessionHTTPExecutor alloc]
          initWithSession:[NSURLSession sessionWithConfiguration:
              NSURLSessionConfiguration.ephemeralSessionConfiguration]]
      sessionStore:sessionStore
      projectIdentityStore:projectIdentityStore
      clientContextProvider:clientContextProvider
      clock:clock
      failureObserver:[self telemetryTransportFailureObserver]];
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:minimumFetchInterval
      timeoutMilliseconds:@(kQONRemoteConfigTransportTimeoutMilliseconds)
      initialBackoffMilliseconds:kQONRemoteConfigInitialBackoffMilliseconds
      maximumBackoffMilliseconds:kQONRemoteConfigMaximumBackoffMilliseconds];
  QONRemoteConfigV2FetchPolicyStore *policyStore =
      [[QONRemoteConfigV2FetchPolicyStore alloc] initWithLocalStorage:localStorage];
  if (!scheduler || !sessionStore || !projectIdentityStore || !transport || !policy ||
      !policyStore) return NO;
  QONRemoteConfigV2FetchCoordinator *coordinator = [[QONRemoteConfigV2FetchCoordinator alloc]
      initWithCore:manager transport:transport policyStore:policyStore clock:clock
      random:[QONRemoteConfigSystemRandom new] scheduler:scheduler policy:policy];
  if (!coordinator) return NO;

  __weak QONRemoteConfigV2GatewayTransport *weakTransport = transport;
  BOOL installed = [self installEngineWithManager:manager
                                      coordinator:coordinator
                                       projectKey:projectKey
                                      environment:environment
                                        scopeSink:^(QONRemoteConfigV2Scope *scope) {
                                          [weakTransport updateScope:scope];
                                        }
                                        scheduler:scheduler
                                    identityQueue:dispatch_queue_create(
                                        "io.qonversion.remote-config-identity",
                                        DISPATCH_QUEUE_SERIAL)];
  if (!installed) return NO;
  // Written once, on the only path that installs an engine, and read as a plain
  // fact afterwards: the engine can never be replaced.
  _installedMinimumFetchIntervalMilliseconds = policy.minimumFetchIntervalMilliseconds;

  // The activation ack rides the very same transport — same session, same
  // bootstrap, same re-bootstrap-once rule — but owns its queue: it does
  // durable I/O, and neither an activation nor a fetch waiter may ever be
  // parked behind it. Installed before the first identity is bound, so the
  // first activation is already reportable; a failure here only means the
  // surface never acknowledges, which the read path does not depend on.
  QONRemoteConfigV2ActivationAckStore *ackStore =
      [[QONRemoteConfigV2ActivationAckStore alloc] initWithLocalStorage:localStorage];
  QONRemoteConfigV2ActivationAckSender *ackSender = ackStore
      ? [[QONRemoteConfigV2ActivationAckSender alloc]
            initWithTransport:transport
                        store:ackStore
                        clock:clock
                       random:[QONRemoteConfigSystemRandom new]
                    scheduler:scheduler
                        queue:dispatch_queue_create("io.qonversion.remote-config-ack",
                                                    DISPATCH_QUEUE_SERIAL)]
      : nil;
  if (ackSender) [self installActivationAckSender:ackSender];

  // The telemetry queue rides the same transport for the same reasons, and owns
  // its own queue for the same reason again: it does durable I/O, and no read,
  // activation or fetch waiter may ever be parked behind it. Installed before
  // the first identity is bound, so the very first read is already reportable.
  QONRemoteConfigV2TelemetryStore *telemetryStore =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:localStorage];
  QONRemoteConfigV2TelemetrySender *telemetrySender = telemetryStore
      ? [[QONRemoteConfigV2TelemetrySender alloc]
            initWithTransport:transport
                        store:telemetryStore
                        clock:clock
                       random:[QONRemoteConfigSystemRandom new]
                    scheduler:scheduler
                        queue:dispatch_queue_create("io.qonversion.remote-config-telemetry",
                                                    DISPATCH_QUEUE_SERIAL)]
      : nil;
  if (telemetrySender) [self installTelemetrySender:telemetrySender];

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
  QONRemoteConfigScopeSink scopeSink = nil;
  dispatch_queue_t identityQueue = nil;
  NSString *projectKey = nil;
  NSString *environment = nil;
  @synchronized (self) {
    manager = self.manager;
    coordinator = self.coordinator;
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
    // The ack queue is unbound with everything else: an activation reported
    // during the window between the unbind and the rebind belongs to no
    // identity, and one identity's session may never vouch for another's.
    [self bindAckScope:nil];
    // Unbinding re-arms the read guard too, so the window between the unbind
    // and the rebind must not accuse the app either.
    [self publishPersistedStateForChange:change manager:manager];
  }
  if (!scope) return;

  dispatch_async(identityQueue, ^{
    @synchronized (self.identityLock) {
      if (self.identityEpoch != epoch) return;
    }
    // The read guard requires all persistent work to finish off the main queue
    // before the scope is bound.
    [manager preloadScopeForReadGuard:scope];
    // Neither a fingerprint nor a project id is supplied here, and neither
    // exists to supply: the fingerprint is a per-response tag that rotates with
    // the user's targeting context, and the project id is learned from the
    // gateway's session bootstrap inside the fetch itself.
    QONRemoteConfigV2FetchBinding *binding =
        [[QONRemoteConfigV2FetchBinding alloc] initWithScope:scope];
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
      // Bound before anything can activate for this identity — which is also
      // where an ack an earlier process queued but never delivered is resumed.
      [self bindAckScope:scope];
      if (!binding || ![binding.scope isEqual:scope]) {
        // Degraded but useful: the persisted configuration of the new identity
        // stays readable even though nothing can fetch for it.
        [manager setScope:scope];
        [self publishPersistedStateForChange:change manager:manager];
        return;
      }
      [coordinator transitionToBinding:binding];
      [self publishPersistedStateForChange:change manager:manager];
    }
    [coordinator fetchWithForceReason:reason
                           completion:^(__unused QONRemoteConfigV2FetchResult *result) {}];
  });
}

/**
 Publishes whatever the newly bound identity already has on disk.

 Binding a scope resets the read guard, so without this an app that correctly
 activated at startup would be accused of reading before activate right after
 an identify or a logout — and on a release build it would keep reading the
 pre-activation state, because the implicit activation is a once-per-lifetime
 budget that the startup read already spent. The first bind is left alone: at
 startup the app is still expected to activate explicitly.
 */
- (void)publishPersistedStateForChange:(QONRemoteConfigControllerIdentityChange)change
                               manager:(QONRemoteConfigV2Manager *)manager {
  if (change == QONRemoteConfigControllerIdentityChangeBuild) return;
  [manager activate];
  // This activation makes a release serve for the newly bound identity, so it
  // owes an ack exactly like an app-driven one. During the unbind half of a
  // switch the ack scope is nil and the offer is dropped.
  [self noteActivatedReleaseNumber:manager.unguardedSnapshot.servedReleaseNumber];
}

#pragma mark - Activation ack

/**
 Rebinds the out-of-band queues and forgets what the previous identity reported.

 The telemetry queue is rebound with the ack queue and for the same reason: an
 observation made while no identity is bound belongs to nobody, and one
 identity's session may never carry another's telemetry.
 */
- (void)bindAckScope:(nullable QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2ActivationAckSender *sender = nil;
  QONRemoteConfigV2TelemetrySender *telemetrySender = nil;
  @synchronized (self.ackLock) {
    sender = self.ackSender;
    telemetrySender = self.telemetrySender;
    self.ackScope = scope;
    self.notedActivationScope = nil;
    self.notedActivationReleaseNumber = 0;
  }
  // Both return immediately: each does its durable read on its own queue, so an
  // identity transition never pays for storage.
  [sender bindScope:scope];
  [telemetrySender bindScope:scope];
}

/**
 Offers `releaseNumber` to the ack queue.

 Every caller is a path the app is waiting on — a `current` read, an `activate`,
 a fetch completion already handed off — so this must stay a comparison and a
 hand-off, never work. The sender's own queue is where the ack is persisted and
 sent, and nothing here can fail in a way the caller could observe.
 */
- (void)noteActivatedReleaseNumber:(NSInteger)releaseNumber {
  if (releaseNumber <= 0) return;
  QONRemoteConfigV2ActivationAckSender *sender = nil;
  QONRemoteConfigV2Scope *scope = nil;
  @synchronized (self.ackLock) {
    sender = self.ackSender;
    scope = self.ackScope;
    if (!sender || !scope) return;
    if (self.notedActivationReleaseNumber == releaseNumber &&
        [self.notedActivationScope isEqual:scope]) {
      return;
    }
    self.notedActivationScope = scope;
    self.notedActivationReleaseNumber = releaseNumber;
  }
  [sender recordActivationForScope:scope releaseNumber:releaseNumber];
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
  if (!manager) return [self fallbackOnlySnapshot];
  QONRemoteConfigSnapshot *snapshot = manager.currentSnapshot;
  // A read can itself activate — the guard's one-shot implicit activation in a
  // release build — and that activation is exactly as ack-worthy as an explicit
  // one. Offered after the snapshot is in hand, so the read never waits.
  [self noteActivatedReleaseNumber:snapshot.servedReleaseNumber];
  return snapshot;
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
  if (!manager) return NO;
  BOOL changed = [manager activate];
  // Offered whether or not the activation changed anything: "unchanged" means
  // the release is already the active one, which is the shape an activation
  // takes after the read guard activated it implicitly — and that release is
  // owed exactly the same ack. Strictly after the activation is complete, and
  // it can neither delay nor fail it.
  [self noteActivatedReleaseNumber:manager.unguardedSnapshot.servedReleaseNumber];
  return changed;
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
  call.completion = nil;
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
    if (!task) {
      // Without a deadline the caller would silently wait the whole policy
      // timeout instead of the one it asked for.
      if ([call claim]) {
        [self deliverStatus:QONRemoteConfigFetchStatusFailed
                   snapshot:manager.unguardedSnapshot
                    changed:NO
       hasPendingActivation:NO
                    forCall:call];
      }
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
    // Strictly after the completion is handed off: the ack queue does durable
    // I/O and the fetch contract promises none of it.
    if (call.shouldActivate) {
      [strongSelf noteActivatedReleaseNumber:manager.unguardedSnapshot.servedReleaseNumber];
    }
    // A round trip that actually reached the gateway is the one moment the
    // network is known to be usable, so it is also the cheapest moment to ship
    // whatever telemetry has accumulated. Same ordering rule: strictly after the
    // caller has been answered.
    if (result.kind == QONRemoteConfigV2FetchResultKindFetched ||
        result.kind == QONRemoteConfigV2FetchResultKindNotModified) {
      [strongSelf noteTelemetryFlushOpportunity];
    }
  }];
}

#pragma mark - Updates

- (id)subscribeOnConfigUpdate:(QONRemoteConfigUpdateHandler)handler {
  if (!handler) return nil;
  QONRemoteConfigSubscription *subscription = [QONRemoteConfigSubscription new];
  subscription.handler = handler;
  QONRemoteConfigV2Manager *manager = nil;
  @synchronized (self) {
    manager = self.manager;
    [self.subscriptions addObject:subscription];
  }
  // Subscribing before configuration must not silently drop the handler: it is
  // registered here when possible and replayed by installEngine otherwise.
  if (manager) {
    subscription.observerToken = [manager addUpdateObserver:handler];
  }
  return subscription;
}

- (void)unsubscribe:(id)token {
  if (![token isKindOfClass:QONRemoteConfigSubscription.class]) return;
  QONRemoteConfigSubscription *subscription = token;
  QONRemoteConfigV2Manager *manager = nil;
  id observerToken = nil;
  @synchronized (self) {
    if (![self.subscriptions containsObject:subscription]) return;
    manager = self.manager;
    observerToken = subscription.observerToken;
    subscription.observerToken = nil;
    [self.subscriptions removeObject:subscription];
  }
  if (observerToken) [manager removeUpdateObserver:observerToken];
}

@end
