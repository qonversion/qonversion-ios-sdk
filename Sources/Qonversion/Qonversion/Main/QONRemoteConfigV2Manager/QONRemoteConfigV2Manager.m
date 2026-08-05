#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigSnapshot+Protected.h"
#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigV2Store.h"

@interface QONRemoteConfigV2Delivery : NSObject
@property (nonatomic, strong) QONRemoteConfigUpdate *update;
@property (nonatomic, copy) NSArray<QONRemoteConfigV2UpdateObserver> *observers;
@property (nonatomic, assign) NSUInteger scopeGeneration;
@end

@implementation QONRemoteConfigV2Delivery
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
@property (nonatomic, strong) NSRecursiveLock *deliveryLock;
@property (nonatomic, assign) BOOL isDrainingDeliveries;
@property (nonatomic, assign) BOOL scopeLoadFailed;
@property (nonatomic, assign) NSUInteger scopeGeneration;
@end

@implementation QONRemoteConfigV2Manager

- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(NSString *)fallbackProjectKey
            fallbackEnvironment:(NSString *)fallbackEnvironment {
  if (!store || (fallbackRelease && (!fallbackProjectKey || !fallbackEnvironment))) return nil;
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
    _deliveryLock = [NSRecursiveLock new];
  }
  return self;
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

- (QONRemoteConfigSnapshot *)currentSnapshot {
  __block QONRemoteConfigSnapshot *snapshot = nil;
  dispatch_sync(self.stateQueue, ^{ snapshot = [self snapshotForState:self.state]; });
  return snapshot;
}

- (QONRemoteConfigSnapshot *)lastFetchedSnapshot {
  __block QONRemoteConfigSnapshot *snapshot = nil;
  dispatch_sync(self.stateQueue, ^{
    if (self.state.candidate) {
      QONRemoteConfigV2Release *previous = [self.state.candidate contentEquals:self.state.active]
          ? self.state.previous : self.state.active;
      snapshot = [[QONRemoteConfigSnapshot alloc] initWithPrimaryRelease:self.state.candidate
          previousRelease:previous fallbackRelease:[self fallbackReleaseForCurrentScopeLocked]];
    }
  });
  return snapshot;
}

- (void)setScope:(QONRemoteConfigV2Scope *)scope {
  [self.deliveryLock lock];
  dispatch_sync(self.stateQueue, ^{
    BOOL sameScope = (self.currentScope == nil && scope == nil) || [self.currentScope isEqual:scope];
    if (sameScope && !(scope && self.scopeLoadFailed)) return;
    if (!sameScope) {
      self.currentScope = [scope copy];
      self.state = [[QONRemoteConfigV2State alloc]
          initWithCandidate:nil active:nil previous:nil didActivate:NO];
      self.scopeLoadFailed = NO;
      self.scopeGeneration += 1;
    }
    if (scope) [self loadScopeStateLocked:scope];
  });
  [self.deliveryLock unlock];
}

- (void)loadScopeStateLocked:(QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2State *loadedState = nil;
  QONRemoteConfigV2StoreLoadStatus status = [self.store loadStateForScope:scope state:&loadedState];
  switch (status) {
    case QONRemoteConfigV2StoreLoadStatusFound:
      self.state = loadedState;
      self.scopeLoadFailed = NO;
      break;
    case QONRemoteConfigV2StoreLoadStatusMissing:
      self.state = [[QONRemoteConfigV2State alloc]
          initWithCandidate:nil active:nil previous:nil didActivate:NO];
      self.scopeLoadFailed = NO;
      break;
    case QONRemoteConfigV2StoreLoadStatusFailed:
      self.scopeLoadFailed = YES;
      break;
  }
}

- (BOOL)ensureCurrentScopeLoadedLocked {
  if (self.currentScope && self.scopeLoadFailed) [self loadScopeStateLocked:self.currentScope];
  return self.currentScope != nil && !self.scopeLoadFailed;
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
  QONRemoteConfigV2State *nextState = [[QONRemoteConfigV2State alloc] initWithCandidate:candidate
      active:candidate previous:self.state.active didActivate:YES];
  QONRemoteConfigV2Scope *scope = self.currentScope;
  if (!scope || ![self.store saveState:nextState forScope:scope]) return nil;
  self.state = nextState;
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

- (void)drainDeliveries {
  [self.deliveryLock lock];
  if (self.isDrainingDeliveries) {
    [self.deliveryLock unlock];
    return;
  }
  self.isDrainingDeliveries = YES;
  @try {
    while (YES) {
      __block QONRemoteConfigV2Delivery *delivery = nil;
      dispatch_sync(self.stateQueue, ^{
        if (self.pendingDeliveries.count > 0) {
          delivery = self.pendingDeliveries.firstObject;
          [self.pendingDeliveries removeObjectAtIndex:0];
        }
      });
      if (!delivery) break;
      for (QONRemoteConfigV2UpdateObserver observer in delivery.observers) {
        __block BOOL isCurrent = NO;
        dispatch_sync(self.stateQueue, ^{
          isCurrent = delivery.scopeGeneration == self.scopeGeneration;
        });
        if (!isCurrent) break;
        @try {
          observer(delivery.update);
        } @catch (__unused NSException *exception) {
          // A committed transition remains successful and later observers still run.
        }
      }
    }
  } @finally {
    self.isDrainingDeliveries = NO;
    [self.deliveryLock unlock];
  }
}

- (void)acceptFetchedRelease:(QONRemoteConfigV2Release *)release
                     forScope:(QONRemoteConfigV2Scope *)scope {
  if (!release || !scope) return;
  __block QONRemoteConfigUpdate *update = nil;
  dispatch_sync(self.stateQueue, ^{
    if (!self.currentScope || ![self.currentScope isEqual:scope]) return;
    if (![self ensureCurrentScopeLoadedLocked]) return;
    QONRemoteConfigV2Release *latest = self.state.candidate;
    if (!latest || self.state.active.releaseNumber > latest.releaseNumber) latest = self.state.active;
    if (latest && release.releaseNumber <= latest.releaseNumber) {
      // Release numbers are monotonic for one project/environment/user scope.
      // Equal-number duplicates and conflicting replays are both no-ops; an
      // older late response must never replace the freshest durable candidate.
      return;
    }
    QONRemoteConfigV2State *nextState = [[QONRemoteConfigV2State alloc]
        initWithCandidate:release active:self.state.active
        previous:self.state.previous didActivate:self.state.didActivate];
    if ([release containsImmediateEntry]) {
      update = [self transitionToCandidateLocked:release];
    } else {
      QONRemoteConfigV2Scope *currentScope = self.currentScope;
      if (currentScope && [self.store saveState:nextState forScope:currentScope]) self.state = nextState;
    }
    if (update) [self enqueueUpdateLocked:update];
  });
  [self drainDeliveries];
}

- (BOOL)activate {
  __block BOOL changed = NO;
  __block QONRemoteConfigUpdate *update = nil;
  dispatch_sync(self.stateQueue, ^{
    if (![self ensureCurrentScopeLoadedLocked]) return;
    if (self.state.candidate) {
      if (self.state.didActivate && [self.state.candidate contentEquals:self.state.active]) return;
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
