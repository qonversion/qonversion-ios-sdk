#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigSnapshot+Protected.h"
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigV2Store.h"

NSString *const QONRemoteConfigV2ReadBeforeActivateAssertionMessage =
    @"Remote Config read before activate(). Call activate() during SDK startup before reading currentSnapshot.";
static void *QONRemoteConfigV2ReadGuardPreloadQueueKey =
    &QONRemoteConfigV2ReadGuardPreloadQueueKey;

@implementation QONRemoteConfigV2ReadGuardPreloadResult

- (instancetype)initWithStatus:(QONRemoteConfigV2ReadGuardPreloadStatus)status
                          state:(QONRemoteConfigV2State *)state {
  if (status < QONRemoteConfigV2ReadGuardPreloadStatusFound ||
      status > QONRemoteConfigV2ReadGuardPreloadStatusPersistenceFailed) return nil;
  if ((status == QONRemoteConfigV2ReadGuardPreloadStatusFound) != (state != nil)) return nil;
  self = [super init];
  if (self) {
    _status = status;
    _state = state;
  }
  return self;
}

@end

@interface QONRemoteConfigV2ReadGuardPreparedSlot : NSObject
@property (nonatomic, strong) QONRemoteConfigV2Scope *scope;
@property (nonatomic, strong) QONRemoteConfigV2State *loadedState;
@property (nonatomic, strong, nullable) QONRemoteConfigV2State *preparedState;
@property (nonatomic, assign) QONRemoteConfigV2ReadGuardPreloadStatus status;
@end

@implementation QONRemoteConfigV2ReadGuardPreparedSlot
@end

@interface QONRemoteConfigV2Delivery : NSObject
@property (nonatomic, strong) QONRemoteConfigUpdate *update;
@property (nonatomic, copy) NSArray<QONRemoteConfigV2UpdateObserver> *observers;
@property (nonatomic, assign) NSUInteger scopeGeneration;
@end

@implementation QONRemoteConfigV2Delivery
@end

@interface QONRemoteConfigV2AdmissionToken ()
@property (nonatomic, strong) NSUUID *ownerNonce;
@property (nonatomic, assign) int64_t ordinal;
@property (nonatomic, strong) QONRemoteConfigV2Scope *scope;
@property (nonatomic, assign) NSUInteger scopeGeneration;
- (instancetype)initPrivate;
@end

@implementation QONRemoteConfigV2AdmissionToken
- (instancetype)initPrivate { return [super init]; }
@end

@interface QONRemoteConfigV2Manager ()
@property (nonatomic, strong) QONRemoteConfigV2Store *store;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Release *fallbackRelease;
@property (nonatomic, copy, nullable) NSString *fallbackProjectKey;
@property (nonatomic, copy, nullable) NSString *fallbackEnvironment;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *currentScope;
@property (nonatomic, strong) QONRemoteConfigV2State *state;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, id> *observers;
@property (nonatomic, strong) NSMutableArray<NSUUID *> *observerOrder;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2Delivery *> *pendingDeliveries;
@property (nonatomic, assign) BOOL isDrainingDeliveries;
@property (nonatomic, assign) BOOL scopeLoadFailed;
@property (nonatomic, assign) NSUInteger scopeGeneration;
@property (nonatomic, assign) int64_t nextAdmissionOrdinal;
@property (nonatomic, strong) NSUUID *admissionOwnerNonce;
@property (nonatomic, strong) id<QONRemoteConfigV2EnvelopeDecoding> envelopeDecoder;
@property (nonatomic, strong) dispatch_queue_t callbackExecutor;
@property (nonatomic, strong) NSObject *callbackExecutorToken;
@property (nonatomic, assign) BOOL callbackExecutorIsMain;
@property (nonatomic, assign) BOOL readGuardEnabled;
@property (nonatomic, assign) QONRemoteConfigV2ReadGuardBuildMode readGuardBuildMode;
@property (nonatomic, copy, nullable) QONRemoteConfigV2ReadGuardAssertionHandler readGuardAssertionHandler;
@property (nonatomic, copy, nullable) QONRemoteConfigV2ReadGuardTelemetryHandler readGuardTelemetryHandler;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2ScopePreloading> scopePreloader;
@property (nonatomic, strong, nullable) QONRemoteConfigV2ReadGuardPreparedSlot *preloadedSlot;
@property (nonatomic, strong, nullable) NSUUID *latestReadGuardPreloadToken;
@property (nonatomic, assign) NSUInteger readGuardScopeSelectionEpoch;
@property (nonatomic, strong, nullable) dispatch_queue_t readGuardPreloadQueue;
@property (nonatomic, strong, nullable) QONRemoteConfigV2State *readGuardBaseState;
@property (nonatomic, strong, nullable) QONRemoteConfigV2State *readGuardPreparedState;
@property (nonatomic, assign) BOOL readGuardFirstReadActivationArmed;
@property (nonatomic, assign) BOOL readGuardFirstReadClaimed;
@property (nonatomic, assign) BOOL readGuardExplicitActivationCalled;
@property (nonatomic, assign) BOOL readGuardLifetimeActivationConsumed;
@property (nonatomic, assign) BOOL readGuardScopeUnavailable;
@property (nonatomic, assign) BOOL readGuardFailSafeEventClaimed;
@end

@implementation QONRemoteConfigV2Manager

- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(NSString *)fallbackProjectKey
            fallbackEnvironment:(NSString *)fallbackEnvironment {
  return [self initWithStore:store fallbackRelease:fallbackRelease
      fallbackProjectKey:fallbackProjectKey fallbackEnvironment:fallbackEnvironment
      envelopeDecoder:[QONRemoteConfigV2EnvelopeParser new]
      callbackExecutor:dispatch_get_main_queue()];
}

- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(NSString *)fallbackProjectKey
            fallbackEnvironment:(NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder {
  return [self initWithStore:store fallbackRelease:fallbackRelease
      fallbackProjectKey:fallbackProjectKey fallbackEnvironment:fallbackEnvironment
      envelopeDecoder:envelopeDecoder callbackExecutor:dispatch_get_main_queue()];
}

- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(NSString *)fallbackProjectKey
            fallbackEnvironment:(NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder
                callbackExecutor:(dispatch_queue_t)callbackExecutor {
  if (!store || !envelopeDecoder || !callbackExecutor ||
      (fallbackRelease && (!fallbackProjectKey || !fallbackEnvironment))) return nil;
  if (fallbackRelease && ![[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:fallbackProjectKey environment:fallbackEnvironment
      canonicalUserID:@"bundle-scope-validation"]) return nil;
  self = [super init];
  if (self) {
    _store = store;
    _fallbackRelease = fallbackRelease;
    _fallbackProjectKey = [fallbackProjectKey copy];
    _fallbackEnvironment = [fallbackEnvironment copy];
    _state = [[QONRemoteConfigV2State alloc] initWithCandidate:nil active:nil previous:nil didActivate:NO];
    _stateQueue = dispatch_queue_create("io.qonversion.remote-config-v2-state", DISPATCH_QUEUE_SERIAL);
    _observers = [NSMutableDictionary new];
    _observerOrder = [NSMutableArray new];
    _pendingDeliveries = [NSMutableArray new];
    _admissionOwnerNonce = NSUUID.UUID;
    _envelopeDecoder = envelopeDecoder;
    _callbackExecutor = callbackExecutor;
    _callbackExecutorToken = [NSObject new];
    _callbackExecutorIsMain = callbackExecutor == dispatch_get_main_queue();
    const void *key = (__bridge const void *)_callbackExecutorToken;
    dispatch_queue_set_specific(callbackExecutor, key, (void *)key, NULL);
  }
  return self;
}

- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(NSString *)fallbackProjectKey
            fallbackEnvironment:(NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder
                callbackExecutor:(dispatch_queue_t)callbackExecutor
              readGuardBuildMode:(QONRemoteConfigV2ReadGuardBuildMode)buildMode
                assertionHandler:(QONRemoteConfigV2ReadGuardAssertionHandler)assertionHandler
                telemetryHandler:(QONRemoteConfigV2ReadGuardTelemetryHandler)telemetryHandler
                  scopePreloader:(id<QONRemoteConfigV2ScopePreloading>)scopePreloader {
  if (!scopePreloader || buildMode < QONRemoteConfigV2ReadGuardBuildModeDebug ||
      buildMode > QONRemoteConfigV2ReadGuardBuildModeRelease) return nil;
  self = [self initWithStore:store fallbackRelease:fallbackRelease
      fallbackProjectKey:fallbackProjectKey fallbackEnvironment:fallbackEnvironment
      envelopeDecoder:envelopeDecoder callbackExecutor:callbackExecutor];
  if (self) {
    _readGuardEnabled = YES;
    _readGuardBuildMode = buildMode;
    _readGuardAssertionHandler = [assertionHandler copy];
    _readGuardTelemetryHandler = [telemetryHandler copy];
    _scopePreloader = scopePreloader;
    _readGuardPreloadQueue = dispatch_queue_create(
        "io.qonversion.remote-config-v2-read-guard-preload", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_readGuardPreloadQueue,
        QONRemoteConfigV2ReadGuardPreloadQueueKey,
        QONRemoteConfigV2ReadGuardPreloadQueueKey, NULL);
  }
  return self;
}

- (QONRemoteConfigV2State *)emptyState {
  return [[QONRemoteConfigV2State alloc]
      initWithCandidate:nil active:nil previous:nil didActivate:NO];
}

- (QONRemoteConfigV2State *)preparedActivationStateFromState:(QONRemoteConfigV2State *)state {
  QONRemoteConfigV2Release *candidate = state.candidate;
  if (candidate && !(state.didActivate && [self release:candidate
      representsSameLocalAdmissionAs:state.active])) {
    return [[QONRemoteConfigV2State alloc] initWithCandidate:candidate active:candidate
        previous:state.active didActivate:YES
        latestAdmissionOrdinal:MAX(state.latestAdmissionOrdinal, candidate.admissionOrdinal)];
  }
  if (!state.didActivate) {
    return [[QONRemoteConfigV2State alloc] initWithCandidate:state.candidate active:state.active
        previous:state.previous didActivate:YES
        latestAdmissionOrdinal:state.latestAdmissionOrdinal];
  }
  return state;
}

- (QONRemoteConfigV2ReadGuardPreloadStatus)preloadScopeForReadGuard:
    (QONRemoteConfigV2Scope *)scope {
  if (!self.readGuardEnabled || !scope || NSThread.isMainThread ||
      dispatch_get_specific(QONRemoteConfigV2ReadGuardPreloadQueueKey)) {
    return QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  }
  NSUUID *token = NSUUID.UUID;
  __block NSUInteger selectionEpoch = 0;
  dispatch_sync(self.stateQueue, ^{
    self.latestReadGuardPreloadToken = token;
    self.preloadedSlot = nil;
    selectionEpoch = self.readGuardScopeSelectionEpoch;
  });

  __block QONRemoteConfigV2ReadGuardPreloadStatus status =
      QONRemoteConfigV2ReadGuardPreloadStatusFailed;
  dispatch_sync(self.readGuardPreloadQueue, ^{
    QONRemoteConfigV2ReadGuardPreloadResult *result = nil;
    @try { result = [self.scopePreloader preloadResultForScope:scope]; }
    @catch (__unused NSException *exception) {}
    status = result ? result.status : QONRemoteConfigV2ReadGuardPreloadStatusFailed;
    QONRemoteConfigV2State *loaded = nil;
    if (status == QONRemoteConfigV2ReadGuardPreloadStatusFound) {
      loaded = result.state;
      if (!loaded) status = QONRemoteConfigV2ReadGuardPreloadStatusCorrupt;
    } else if (status == QONRemoteConfigV2ReadGuardPreloadStatusMissing) {
      loaded = [self emptyState];
    }
    if (!loaded) loaded = [self emptyState];

    QONRemoteConfigV2ReadGuardPreparedSlot *slot = [QONRemoteConfigV2ReadGuardPreparedSlot new];
    slot.scope = [scope copy];
    slot.loadedState = loaded;
    dispatch_sync(self.stateQueue, ^{
      if (![self.latestReadGuardPreloadToken isEqual:token] ||
          self.readGuardScopeSelectionEpoch != selectionEpoch) {
        status = QONRemoteConfigV2ReadGuardPreloadStatusFailed;
        return;
      }
      QONRemoteConfigV2State *prepared = nil;
      BOOL canPrepare =
          self.readGuardBuildMode == QONRemoteConfigV2ReadGuardBuildModeRelease &&
          !self.readGuardLifetimeActivationConsumed &&
          (status == QONRemoteConfigV2ReadGuardPreloadStatusFound ||
           status == QONRemoteConfigV2ReadGuardPreloadStatusMissing);
      if (canPrepare) {
        prepared = [self preparedActivationStateFromState:loaded];
        if (prepared != loaded && ![self.store saveState:prepared forScope:scope]) {
          prepared = nil;
          status = QONRemoteConfigV2ReadGuardPreloadStatusPersistenceFailed;
        }
      }
      slot.preparedState = prepared;
      slot.status = status;
      self.preloadedSlot = slot;
    });
  });
  return status;
}

- (QONRemoteConfigV2Release *)fallbackReleaseForCurrentScopeLocked {
  if (!self.fallbackRelease || !self.currentScope) return self.fallbackRelease;
  NSString *projectKey = self.fallbackProjectKey;
  NSString *environment = self.fallbackEnvironment;
  if (!projectKey || !environment) return nil;
  return [self.currentScope.projectKey isEqualToString:projectKey] &&
      [self.currentScope.environment isEqualToString:environment]
      ? self.fallbackRelease : nil;
}

- (QONRemoteConfigSnapshot *)snapshotForState:(QONRemoteConfigV2State *)state {
  return [[QONRemoteConfigSnapshot alloc] initWithPrimaryRelease:state.active
      previousRelease:state.previous fallbackRelease:[self fallbackReleaseForCurrentScopeLocked]];
}

- (void)emitReadGuardTelemetry:(QONRemoteConfigV2ReadGuardTelemetryEvent)event {
  QONRemoteConfigV2ReadGuardTelemetryHandler handler = self.readGuardTelemetryHandler;
  if (!handler) return;
  dispatch_async(self.callbackExecutor, ^{
    @try { handler(event); }
    @catch (__unused NSException *exception) {}
  });
}

- (void)scheduleReadGuardDeliveryDrain {
  dispatch_async(self.callbackExecutor, ^{ [self drainDeliveriesOnCallbackExecutor]; });
}

- (QONRemoteConfigSnapshot *)currentSnapshot {
  __block QONRemoteConfigSnapshot *snapshot = nil;
  __block QONRemoteConfigV2ReadGuardAssertionHandler assertionHandler = nil;
  __block BOOL emitReadBeforeActivate = NO;
  __block BOOL emitImplicitActivation = NO;
  __block BOOL emitPreloadAbsent = NO;
  __block BOOL drainDeliveries = NO;
  dispatch_sync(self.stateQueue, ^{
    BOOL scopeBindingPending = self.latestReadGuardPreloadToken != nil;
    if (self.readGuardEnabled && !scopeBindingPending &&
        !self.readGuardExplicitActivationCalled &&
        !self.readGuardFirstReadClaimed) {
      self.readGuardFirstReadClaimed = YES;
      if (self.readGuardBuildMode == QONRemoteConfigV2ReadGuardBuildModeDebug) {
        assertionHandler = self.readGuardAssertionHandler;
      } else {
        emitReadBeforeActivate = YES;
        BOOL activationArmed = !self.readGuardLifetimeActivationConsumed &&
            self.readGuardFirstReadActivationArmed;
        self.readGuardLifetimeActivationConsumed = YES;
        self.readGuardFirstReadActivationArmed = NO;
        if (activationArmed && self.readGuardPreparedState &&
            self.state == self.readGuardBaseState) {
          emitImplicitActivation = self.readGuardPreparedState != self.readGuardBaseState;
          QONRemoteConfigSnapshot *oldSnapshot = [self snapshotForState:self.state];
          self.state = self.readGuardPreparedState;
          self.nextAdmissionOrdinal = MAX(self.nextAdmissionOrdinal,
                                           self.state.latestAdmissionOrdinal);
          QONRemoteConfigUpdate *update = [self updateFromSnapshot:oldSnapshot
                                                           toState:self.state];
          if (update.changedKeys.count > 0) {
            [self enqueueUpdateLocked:update];
            drainDeliveries = YES;
          }
        }
        self.readGuardBaseState = nil;
        self.readGuardPreparedState = nil;
      }
    }
    if (self.readGuardEnabled && !self.currentScope &&
        !self.readGuardFailSafeEventClaimed) {
      self.readGuardFailSafeEventClaimed = YES;
      emitPreloadAbsent = YES;
    }
    snapshot = [self snapshotForState:self.state];
  });
  if (assertionHandler) {
    @try { assertionHandler(QONRemoteConfigV2ReadBeforeActivateAssertionMessage); }
    @catch (__unused NSException *exception) {}
  }
  if (emitReadBeforeActivate) {
    [self emitReadGuardTelemetry:QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate];
  }
  if (emitImplicitActivation) {
    [self emitReadGuardTelemetry:QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation];
  }
  if (emitPreloadAbsent) {
    [self emitReadGuardTelemetry:QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent];
  }
  if (drainDeliveries) [self scheduleReadGuardDeliveryDrain];
  return snapshot;
}

- (QONRemoteConfigSnapshot *)unguardedSnapshot {
  __block QONRemoteConfigSnapshot *snapshot = nil;
  dispatch_sync(self.stateQueue, ^{ snapshot = [self snapshotForState:self.state]; });
  return snapshot;
}

- (BOOL)release:(QONRemoteConfigV2Release *)release
    representsSameLocalAdmissionAs:(QONRemoteConfigV2Release *)other {
  if (!release || !other) return NO;
  if (release.admissionOrdinal > 0 || other.admissionOrdinal > 0) {
    return release.admissionOrdinal > 0 && release.admissionOrdinal == other.admissionOrdinal;
  }
  return [release contentEquals:other];
}

- (QONRemoteConfigSnapshot *)lastFetchedSnapshot {
  __block QONRemoteConfigSnapshot *snapshot = nil;
  dispatch_sync(self.stateQueue, ^{
    if (self.state.candidate) {
      QONRemoteConfigV2Release *previous = [self release:self.state.candidate
          representsSameLocalAdmissionAs:self.state.active]
          ? self.state.previous : self.state.active;
      snapshot = [[QONRemoteConfigSnapshot alloc] initWithPrimaryRelease:self.state.candidate
          previousRelease:previous fallbackRelease:[self fallbackReleaseForCurrentScopeLocked]];
    }
  });
  return snapshot;
}

- (QONRemoteConfigV2ConditionalRequestValidator *)conditionalRequestValidatorForHeadLocked {
  QONRemoteConfigV2Release *head = self.state.candidate ?: self.state.active;
  if (!head.canonicalBody || head.strongETag.length != 66 || head.admissionOrdinal <= 0) return nil;
  NSString *bodyDigest = [head.strongETag substringWithRange:NSMakeRange(1, 64)];
  return [[QONRemoteConfigV2ConditionalRequestValidator alloc]
      initWithStrongETag:head.strongETag bodyDigest:bodyDigest
      headAdmissionOrdinal:head.admissionOrdinal];
}

- (QONRemoteConfigV2ConditionalRequestValidator *)conditionalRequestValidator {
  __block QONRemoteConfigV2ConditionalRequestValidator *validator = nil;
  dispatch_sync(self.stateQueue, ^{ validator = [self conditionalRequestValidatorForHeadLocked]; });
  return validator;
}

- (BOOL)isConditionalRequestValidatorCurrent:(QONRemoteConfigV2ConditionalRequestValidator *)validator {
  if (!validator) return NO;
  __block BOOL current = NO;
  dispatch_sync(self.stateQueue, ^{
    current = [[self conditionalRequestValidatorForHeadLocked] isEqual:validator];
  });
  return current;
}

- (void)applyScopeLocked:(QONRemoteConfigV2Scope *)scope {
  if (self.readGuardEnabled) {
    __block BOOL emitFailSafe = NO;
    __block QONRemoteConfigV2ReadGuardTelemetryEvent failSafeEvent =
        QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent;
    dispatch_sync(self.stateQueue, ^{
      self.readGuardScopeSelectionEpoch += 1;
      self.latestReadGuardPreloadToken = nil;
      QONRemoteConfigV2ReadGuardPreparedSlot *availableSlot = self.preloadedSlot;
      self.preloadedSlot = nil;
      BOOL sameScope = (self.currentScope == nil && scope == nil) ||
          [self.currentScope isEqual:scope];
      BOOL hasExactPreload = scope && [availableSlot.scope isEqual:scope];
      if (sameScope && !hasExactPreload) return;

      if (!sameScope) {
        self.currentScope = [scope copy];
        self.state = [self emptyState];
        self.scopeLoadFailed = NO;
        self.nextAdmissionOrdinal = 0;
        self.scopeGeneration += 1;
      } else if (hasExactPreload) {
        // A freshly preloaded state starts a new read/observer generation even
        // when the logical scope is unchanged.
        self.scopeGeneration += 1;
      }
      self.readGuardBaseState = nil;
      self.readGuardPreparedState = nil;
      self.readGuardFirstReadActivationArmed = NO;
      self.readGuardFirstReadClaimed = NO;
      self.readGuardExplicitActivationCalled = NO;
      self.readGuardScopeUnavailable = scope != nil;
      self.readGuardFailSafeEventClaimed = NO;

      if (!scope) return;
      if (hasExactPreload) {
        QONRemoteConfigV2ReadGuardPreparedSlot *slot = availableSlot;
        self.state = slot.loadedState;
        self.nextAdmissionOrdinal = slot.loadedState.latestAdmissionOrdinal;
        self.readGuardBaseState = slot.loadedState;
        self.readGuardPreparedState = slot.preparedState;
        self.readGuardFirstReadActivationArmed =
            self.readGuardBuildMode == QONRemoteConfigV2ReadGuardBuildModeRelease &&
            !self.readGuardLifetimeActivationConsumed &&
            slot.status != QONRemoteConfigV2ReadGuardPreloadStatusFailed &&
            slot.status != QONRemoteConfigV2ReadGuardPreloadStatusCorrupt;
        self.readGuardScopeUnavailable =
            slot.status == QONRemoteConfigV2ReadGuardPreloadStatusFailed ||
            slot.status == QONRemoteConfigV2ReadGuardPreloadStatusCorrupt;
        switch (slot.status) {
          case QONRemoteConfigV2ReadGuardPreloadStatusFound:
            break;
          case QONRemoteConfigV2ReadGuardPreloadStatusMissing:
            failSafeEvent = QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent;
            emitFailSafe = YES;
            break;
          case QONRemoteConfigV2ReadGuardPreloadStatusFailed:
            failSafeEvent = QONRemoteConfigV2ReadGuardTelemetryEventPreloadFailed;
            emitFailSafe = YES;
            break;
          case QONRemoteConfigV2ReadGuardPreloadStatusCorrupt:
            failSafeEvent = QONRemoteConfigV2ReadGuardTelemetryEventPreloadCorrupt;
            emitFailSafe = YES;
            break;
          case QONRemoteConfigV2ReadGuardPreloadStatusPersistenceFailed:
            failSafeEvent =
                QONRemoteConfigV2ReadGuardTelemetryEventPreparedActivationPersistenceFailed;
            emitFailSafe = YES;
            break;
        }
      } else {
        failSafeEvent = QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent;
        emitFailSafe = YES;
      }
      if (emitFailSafe) self.readGuardFailSafeEventClaimed = YES;
    });
    if (emitFailSafe) [self emitReadGuardTelemetry:failSafeEvent];
    return;
  }
  dispatch_sync(self.stateQueue, ^{
    BOOL sameScope = (self.currentScope == nil && scope == nil) || [self.currentScope isEqual:scope];
    if (sameScope && !(scope && self.scopeLoadFailed)) return;
    if (!sameScope) {
      self.currentScope = [scope copy];
      self.state = [[QONRemoteConfigV2State alloc]
          initWithCandidate:nil active:nil previous:nil didActivate:NO];
      self.scopeLoadFailed = NO;
      self.nextAdmissionOrdinal = 0;
      self.scopeGeneration += 1;
    }
    if (scope) [self loadScopeStateLocked:scope];
  });
}

- (void)setScope:(QONRemoteConfigV2Scope *)scope {
  [self applyScopeLocked:[scope copy]];
}

- (void)loadScopeStateLocked:(QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2State *loadedState = nil;
  QONRemoteConfigV2StoreLoadStatus status = [self.store loadStateForScope:scope state:&loadedState];
  switch (status) {
    case QONRemoteConfigV2StoreLoadStatusFound:
      self.state = loadedState;
      self.nextAdmissionOrdinal = loadedState.latestAdmissionOrdinal;
      self.scopeLoadFailed = NO;
      break;
    case QONRemoteConfigV2StoreLoadStatusMissing:
      self.state = [[QONRemoteConfigV2State alloc]
          initWithCandidate:nil active:nil previous:nil didActivate:NO];
      self.nextAdmissionOrdinal = 0;
      self.scopeLoadFailed = NO;
      break;
    case QONRemoteConfigV2StoreLoadStatusFailed:
      self.scopeLoadFailed = YES;
      break;
  }
}

- (BOOL)ensureCurrentScopeLoadedLocked {
  if (self.readGuardEnabled) {
    return self.currentScope != nil && !self.readGuardScopeUnavailable;
  }
  if (self.currentScope && self.scopeLoadFailed) [self loadScopeStateLocked:self.currentScope];
  return self.currentScope != nil && !self.scopeLoadFailed;
}

- (void)invalidateReadGuardPreparationLocked {
  if (!self.readGuardEnabled) return;
  self.readGuardBaseState = nil;
  self.readGuardPreparedState = nil;
  self.readGuardFirstReadActivationArmed = NO;
}

- (QONRemoteConfigV2State *)durableStateForReadGuardProposedStateLocked:
    (QONRemoteConfigV2State *)proposedState {
  if (!self.readGuardEnabled || !self.readGuardFirstReadActivationArmed) {
    return proposedState;
  }
  return [self preparedActivationStateFromState:proposedState];
}

- (void)didCommitReadGuardProposedStateLocked:(QONRemoteConfigV2State *)proposedState
                                 durableState:(QONRemoteConfigV2State *)durableState {
  if (self.readGuardEnabled && self.readGuardFirstReadActivationArmed) {
    self.readGuardBaseState = proposedState;
    self.readGuardPreparedState = durableState;
  } else {
    [self invalidateReadGuardPreparationLocked];
  }
}

- (NSSet<NSString *> *)changedKeysFrom:(QONRemoteConfigSnapshot *)oldSnapshot
                                    to:(QONRemoteConfigSnapshot *)newSnapshot {
  NSMutableSet *keys = oldSnapshot ? [oldSnapshot.allKeys mutableCopy] : [NSMutableSet new];
  [keys unionSet:newSnapshot.allKeys];
  NSMutableSet *changed = [NSMutableSet new];
  for (NSString *key in keys) {
    QONRemoteConfigV2Entry *oldEntry = [oldSnapshot effectiveEntryForKey:key];
    QONRemoteConfigV2Entry *newEntry = [newSnapshot effectiveEntryForKey:key];
    BOOL equal = (oldEntry == nil && newEntry == nil) || [oldEntry contentEquals:newEntry];
    if (!equal) [changed addObject:key];
  }
  return [changed copy];
}

- (QONRemoteConfigUpdate *)transitionToCandidateLocked:(QONRemoteConfigV2Release *)candidate {
  QONRemoteConfigSnapshot *oldSnapshot = [self snapshotForState:self.state];
  if (!candidate) return nil;
  int64_t latestAdmissionOrdinal = MAX(self.state.latestAdmissionOrdinal,
                                       candidate.admissionOrdinal);
  QONRemoteConfigV2State *nextState = [[QONRemoteConfigV2State alloc] initWithCandidate:candidate
      active:candidate previous:self.state.active didActivate:YES
      latestAdmissionOrdinal:latestAdmissionOrdinal];
  QONRemoteConfigV2Scope *scope = self.currentScope;
  QONRemoteConfigV2State *durableState =
      [self durableStateForReadGuardProposedStateLocked:nextState];
  if (!scope || ![self.store saveState:durableState forScope:scope]) return nil;
  self.state = nextState;
  [self didCommitReadGuardProposedStateLocked:nextState durableState:durableState];
  QONRemoteConfigSnapshot *newSnapshot = [self snapshotForState:self.state];
  NSSet *changed = [self changedKeysFrom:oldSnapshot to:newSnapshot];
  NSMutableDictionary *metadata = [NSMutableDictionary new];
  for (NSString *key in changed) {
    id value = [newSnapshot metadataForKey:key];
    if (value) metadata[key] = value;
  }
  return [[QONRemoteConfigUpdate alloc] initWithSnapshot:newSnapshot changedKeys:changed metadataByKey:metadata];
}

- (NSArray<QONRemoteConfigV2UpdateObserver> *)observerSnapshotLocked {
  NSMutableArray *snapshot = [NSMutableArray arrayWithCapacity:self.observerOrder.count];
  for (NSUUID *token in self.observerOrder) {
    id observer = self.observers[token];
    if (observer) [snapshot addObject:observer];
  }
  return [snapshot copy];
}

- (void)enqueueUpdateLocked:(QONRemoteConfigUpdate *)update {
  if (update.changedKeys.count == 0) return;
  QONRemoteConfigV2Delivery *delivery = [QONRemoteConfigV2Delivery new];
  delivery.update = update;
  delivery.observers = [self observerSnapshotLocked];
  delivery.scopeGeneration = self.scopeGeneration;
  [self.pendingDeliveries addObject:delivery];
}

- (BOOL)isOnCallbackExecutor {
  if (self.callbackExecutorIsMain && NSThread.isMainThread) return YES;
  const void *key = (__bridge const void *)self.callbackExecutorToken;
  return dispatch_get_specific(key) == key;
}

- (void)drainDeliveriesOnCallbackExecutor {
  NSAssert([self isOnCallbackExecutor], @"Remote Config callback executor must be serial");
  if (self.isDrainingDeliveries) return;
  self.isDrainingDeliveries = YES;
  @try {
    while (YES) {
      __block QONRemoteConfigV2Delivery *delivery = nil;
      dispatch_sync(self.stateQueue, ^{
        while (self.pendingDeliveries.count > 0 && !delivery) {
          QONRemoteConfigV2Delivery *candidate = self.pendingDeliveries.firstObject;
          [self.pendingDeliveries removeObjectAtIndex:0];
          if (candidate.scopeGeneration == self.scopeGeneration) delivery = candidate;
        }
      });
      if (!delivery) return;

      for (QONRemoteConfigV2UpdateObserver observer in delivery.observers) {
        // The generation check is the atomic claim point. setScope may return
        // after this point while this one callback is still executing.
        __block BOOL claimed = NO;
        dispatch_sync(self.stateQueue, ^{
          claimed = delivery.scopeGeneration == self.scopeGeneration;
        });
        if (!claimed) break;
        @try {
          observer(delivery.update);
        } @catch (__unused NSException *exception) {
          // A committed transition remains successful and later observers still run.
        }
      }
    }
  } @finally {
    self.isDrainingDeliveries = NO;
  }
}

- (void)drainDeliveries {
  if ([self isOnCallbackExecutor]) {
    [self drainDeliveriesOnCallbackExecutor];
  } else {
    dispatch_async(self.callbackExecutor, ^{
      [self drainDeliveriesOnCallbackExecutor];
    });
  }
}

- (QONRemoteConfigV2AdmissionToken *)beginAdmissionForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return nil;
  __block QONRemoteConfigV2AdmissionToken *token = nil;
  dispatch_sync(self.stateQueue, ^{
    if (![self.currentScope isEqual:scope] || ![self ensureCurrentScopeLoadedLocked] ||
        self.nextAdmissionOrdinal == INT64_MAX) return;
    self.nextAdmissionOrdinal += 1;
    token = [[QONRemoteConfigV2AdmissionToken alloc] initPrivate];
    token.ownerNonce = self.admissionOwnerNonce;
    token.ordinal = self.nextAdmissionOrdinal;
    token.scope = [scope copy];
    token.scopeGeneration = self.scopeGeneration;
  });
  return token;
}

- (BOOL)admissionTokenIsCurrentLocked:(QONRemoteConfigV2AdmissionToken *)token {
  return token && [token.ownerNonce isEqual:self.admissionOwnerNonce] &&
      [token.scope isEqual:self.currentScope] && token.scopeGeneration == self.scopeGeneration &&
      token.ordinal == self.nextAdmissionOrdinal &&
      token.ordinal > self.state.latestAdmissionOrdinal;
}

- (QONRemoteConfigV2Release *)releaseByTombstoningMissingActiveKeys:
    (QONRemoteConfigV2Release *)release {
  if (!self.state.active) return release;
  NSMutableDictionary *entries = [release.entries mutableCopy];
  for (NSString *key in self.state.active.entries) {
    QONRemoteConfigV2Entry *activeEntry = self.state.active.entries[key];
    if (!activeEntry.isTombstone && !entries[key]) {
      QONRemoteConfigV2Entry *tombstone = [[QONRemoteConfigV2Entry alloc] initWithTombstoneKey:key];
      if (!tombstone) return nil;
      entries[key] = tombstone;
    }
  }
  if (entries.count == release.entries.count) return release;
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:release.releaseUID
      releaseNumber:release.releaseNumber manifestContentHash:release.manifestContentHash
      entries:entries canonicalBody:release.canonicalBody strongETag:release.strongETag
      projectID:release.projectID contextFingerprint:release.contextFingerprint
      admissionOrdinal:release.admissionOrdinal];
}

- (QONRemoteConfigUpdate *)updateFromSnapshot:(QONRemoteConfigSnapshot *)oldSnapshot
                                     toState:(QONRemoteConfigV2State *)state {
  QONRemoteConfigSnapshot *newSnapshot = [self snapshotForState:state];
  NSSet *changed = [self changedKeysFrom:oldSnapshot to:newSnapshot];
  NSMutableDictionary *metadata = [NSMutableDictionary new];
  for (NSString *key in changed) {
    id value = [newSnapshot metadataForKey:key];
    if (value) metadata[key] = value;
  }
  return [[QONRemoteConfigUpdate alloc] initWithSnapshot:newSnapshot
      changedKeys:changed metadataByKey:metadata];
}

- (QONRemoteConfigV2TransitionStatus)admitBody:(NSData *)body
                                   strongETag:(NSString *)strongETag
                                    projectID:(int64_t)projectID
                               admissionToken:(QONRemoteConfigV2AdmissionToken *)admissionToken {
  if (!body || !strongETag || !admissionToken) return QONRemoteConfigV2TransitionStatusRejected;
  // Built here, from the id this fetch learned and the environment the token was
  // opened for. A learned id that is out of range yields no expectation at all,
  // which refuses the body rather than admitting it unconstrained.
  QONRemoteConfigV2EnvelopeExpectation *expectation =
      [[QONRemoteConfigV2EnvelopeExpectation alloc]
          initWithProjectID:projectID
             environmentUID:admissionToken.scope.environment];
  if (!expectation) return QONRemoteConfigV2TransitionStatusRejected;
  __block BOOL tokenWasCurrent = NO;
  dispatch_sync(self.stateQueue, ^{
    tokenWasCurrent = [self admissionTokenIsCurrentLocked:admissionToken];
  });
  if (!tokenWasCurrent) return QONRemoteConfigV2TransitionStatusRejected;
  QONRemoteConfigV2Envelope *envelope = [self.envelopeDecoder parseBody:body
      strongETag:strongETag expectation:expectation];
  if (!envelope) return QONRemoteConfigV2TransitionStatusRejected;

  __block QONRemoteConfigV2TransitionStatus status = QONRemoteConfigV2TransitionStatusRejected;
  dispatch_sync(self.stateQueue, ^{
    if (![self admissionTokenIsCurrentLocked:admissionToken] ||
        ![self ensureCurrentScopeLoadedLocked]) return;
    NSInteger releaseFloor = MAX(self.state.candidate.releaseNumber,
                                 self.state.active.releaseNumber);
    if (envelope.snapshotRelease.releaseNumber < releaseFloor) return;
    QONRemoteConfigV2Release *tokenized = [envelope.snapshotRelease
        releaseBySettingAdmissionOrdinal:admissionToken.ordinal];
    QONRemoteConfigV2Release *admitted = [self releaseByTombstoningMissingActiveKeys:tokenized];
    if (!admitted) return;
    QONRemoteConfigSnapshot *oldSnapshot = [self snapshotForState:self.state];
    BOOL immediate = admitted.containsImmediateEntry;
    QONRemoteConfigV2State *nextState = [[QONRemoteConfigV2State alloc]
        initWithCandidate:admitted
                   active:immediate ? admitted : self.state.active
                 previous:immediate ? self.state.active : self.state.previous
              didActivate:immediate ? YES : self.state.didActivate
   latestAdmissionOrdinal:admissionToken.ordinal];
    QONRemoteConfigV2State *durableState = nextState ?
        [self durableStateForReadGuardProposedStateLocked:nextState] : nil;
    if (!durableState || !self.currentScope ||
        ![self.store saveState:durableState forScope:self.currentScope]) {
      status = QONRemoteConfigV2TransitionStatusPersistenceFailed;
      return;
    }
    self.state = nextState;
    [self didCommitReadGuardProposedStateLocked:nextState durableState:durableState];
    if (immediate) {
      QONRemoteConfigUpdate *update = [self updateFromSnapshot:oldSnapshot toState:nextState];
      [self enqueueUpdateLocked:update];
      status = QONRemoteConfigV2TransitionStatusActivated;
    } else {
      status = QONRemoteConfigV2TransitionStatusAccepted;
    }
  });
  [self drainDeliveries];
  return status;
}

- (void)acceptFetchedRelease:(QONRemoteConfigV2Release *)release
                     forScope:(QONRemoteConfigV2Scope *)scope {
  if (!release || !scope) return;
  __block QONRemoteConfigUpdate *update = nil;
  __block int64_t admissionOrdinal = 0;
  dispatch_sync(self.stateQueue, ^{
    if (!self.currentScope || ![self.currentScope isEqual:scope]) return;
    if (![self ensureCurrentScopeLoadedLocked]) return;
    if (self.nextAdmissionOrdinal == INT64_MAX) return;
    QONRemoteConfigV2Release *latest = self.state.candidate;
    if (!latest || self.state.active.releaseNumber > latest.releaseNumber) latest = self.state.active;
    if (latest && release.releaseNumber <= latest.releaseNumber) {
      // Release numbers are monotonic for one project/environment/user scope.
      // Equal-number duplicates and conflicting replays are both no-ops; an
      // older late response must never replace the freshest durable candidate.
      return;
    }
    self.nextAdmissionOrdinal += 1;
    admissionOrdinal = self.nextAdmissionOrdinal;
    QONRemoteConfigV2Release *orderedRelease = [release
        releaseBySettingAdmissionOrdinal:admissionOrdinal];
    if (!orderedRelease) return;
    QONRemoteConfigV2State *nextState = [[QONRemoteConfigV2State alloc]
        initWithCandidate:orderedRelease active:self.state.active
        previous:self.state.previous didActivate:self.state.didActivate
        latestAdmissionOrdinal:admissionOrdinal];
    if ([orderedRelease containsImmediateEntry]) {
      update = [self transitionToCandidateLocked:orderedRelease];
    } else {
      QONRemoteConfigV2Scope *currentScope = self.currentScope;
      QONRemoteConfigV2State *durableState =
          [self durableStateForReadGuardProposedStateLocked:nextState];
      if (currentScope && [self.store saveState:durableState forScope:currentScope]) {
        self.state = nextState;
        [self didCommitReadGuardProposedStateLocked:nextState durableState:durableState];
      }
    }
    if (update) [self enqueueUpdateLocked:update];
  });
  [self drainDeliveries];
}

- (BOOL)activate {
  __block BOOL changed = NO;
  __block QONRemoteConfigUpdate *update = nil;
  dispatch_sync(self.stateQueue, ^{
    if (self.readGuardEnabled) {
      self.readGuardExplicitActivationCalled = YES;
      self.readGuardLifetimeActivationConsumed = YES;
    }
    if (![self ensureCurrentScopeLoadedLocked]) return;
    if (self.readGuardEnabled && self.readGuardPreparedState &&
        self.state == self.readGuardBaseState) {
      QONRemoteConfigSnapshot *oldSnapshot = [self snapshotForState:self.state];
      self.state = self.readGuardPreparedState;
      self.nextAdmissionOrdinal = MAX(self.nextAdmissionOrdinal,
                                       self.state.latestAdmissionOrdinal);
      update = [self updateFromSnapshot:oldSnapshot toState:self.state];
      changed = update.changedKeys.count > 0;
      [self invalidateReadGuardPreparationLocked];
      if (update) [self enqueueUpdateLocked:update];
      return;
    }
    [self invalidateReadGuardPreparationLocked];
    if (self.state.candidate) {
      if (self.state.didActivate && [self release:self.state.candidate
          representsSameLocalAdmissionAs:self.state.active]) return;
      update = [self transitionToCandidateLocked:self.state.candidate];
      changed = update.changedKeys.count > 0;
    } else if (!self.state.didActivate) {
      QONRemoteConfigV2State *nextState = [[QONRemoteConfigV2State alloc]
          initWithCandidate:nil active:nil previous:nil didActivate:YES];
      QONRemoteConfigV2Scope *scope = self.currentScope;
      if (!scope || ![self.store saveState:nextState forScope:scope]) return;
      QONRemoteConfigSnapshot *snapshot = [self snapshotForState:self.state];
      self.state = nextState;
      NSSet *changedKeys = [self changedKeysFrom:nil to:snapshot];
      NSMutableDictionary *metadata = [NSMutableDictionary new];
      for (NSString *key in changedKeys) {
        id value = [snapshot metadataForKey:key];
        if (value) metadata[key] = value;
      }
      update = [[QONRemoteConfigUpdate alloc] initWithSnapshot:snapshot
          changedKeys:changedKeys metadataByKey:metadata];
      changed = changedKeys.count > 0;
    }
    if (update) [self enqueueUpdateLocked:update];
  });
  [self drainDeliveries];
  return changed;
}

- (id)addUpdateObserver:(QONRemoteConfigV2UpdateObserver)observer {
  if (!observer) return nil;
  NSUUID *token = NSUUID.UUID;
  dispatch_sync(self.stateQueue, ^{
    self.observers[token] = [observer copy];
    [self.observerOrder addObject:token];
  });
  return token;
}

- (void)removeUpdateObserver:(id)token {
  if (!token) return;
  dispatch_sync(self.stateQueue, ^{
    [self.observers removeObjectForKey:token];
    [self.observerOrder removeObject:token];
  });
}

@end
