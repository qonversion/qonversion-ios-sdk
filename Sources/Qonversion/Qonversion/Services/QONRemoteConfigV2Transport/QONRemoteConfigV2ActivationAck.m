#import "QONRemoteConfigV2ActivationAck.h"
#import "QNLocalStorage.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NSInteger const QONRemoteConfigV2ActivationAckMaximumAttempts = 3;
int64_t const QONRemoteConfigV2ActivationAckInitialRetryDelayMilliseconds = 1000;
int64_t const QONRemoteConfigV2ActivationAckMaximumRetryDelayMilliseconds = 30000;

static NSInteger const QONRemoteConfigV2ActivationAckSchema = 1;
static NSString *const QONRemoteConfigV2ActivationAckPrefix =
    @"com.qonversion.keys.remote-config-v2-ack.";
static int64_t const QONRemoteConfigV2ActivationAckMinimumRetryDelayMilliseconds = 1;
static double const QONRemoteConfigV2ActivationAckSafeJitter = 0.5;

#pragma mark - Shared helpers

static BOOL QONRemoteConfigV2AckExactInt64(id object, int64_t *value) {
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

static void QONRemoteConfigV2AckAppendFramed(NSMutableData *data, NSData *value) {
  uint32_t length = CFSwapInt32HostToBig((uint32_t)value.length);
  [data appendBytes:&length length:sizeof(length)];
  [data appendData:value];
}

static NSString *QONRemoteConfigV2AckSHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return [hex copy];
}

#pragma mark - Model

@implementation QONRemoteConfigV2ActivationAck

- (instancetype)initWithReleaseNumber:(int64_t)releaseNumber
                   activatedAtSeconds:(int64_t)activatedAtSeconds {
  // A zero timestamp would be indistinguishable from "absent" in the durable
  // record and would make the queued ack silently un-persistable.
  if (releaseNumber <= 0 || releaseNumber > QONRemoteConfigV2MaximumSafeInteger ||
      activatedAtSeconds <= 0 || activatedAtSeconds > QONRemoteConfigV2MaximumSafeInteger) {
    return nil;
  }
  self = [super init];
  if (self) {
    _releaseNumber = releaseNumber;
    _activatedAtSeconds = activatedAtSeconds;
  }
  return self;
}

- (id)copyWithZone:(__unused NSZone *)zone {
  return self;
}

- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2ActivationAck.class]) return NO;
  QONRemoteConfigV2ActivationAck *other = object;
  return self.releaseNumber == other.releaseNumber &&
      self.activatedAtSeconds == other.activatedAtSeconds;
}

- (NSUInteger)hash {
  return (NSUInteger)(self.releaseNumber ^ self.activatedAtSeconds);
}

@end

@implementation QONRemoteConfigV2ActivationAckRecord

- (instancetype)initWithPending:(QONRemoteConfigV2ActivationAck *)pending
           settledReleaseNumber:(int64_t)settledReleaseNumber {
  if (settledReleaseNumber < 0 || settledReleaseNumber > QONRemoteConfigV2MaximumSafeInteger) {
    return nil;
  }
  self = [super init];
  if (self) {
    _pending = pending;
    _settledReleaseNumber = settledReleaseNumber;
  }
  return self;
}

- (id)copyWithZone:(__unused NSZone *)zone {
  return self;
}

@end

#pragma mark - Attempt

/**
 One delivery attempt.

 `answered` makes the completion single-shot independently of the transport: a
 transport that both calls back and throws must not advance the retry budget
 twice. It is only ever touched on the sender's queue.
 */
@interface QONRemoteConfigV2ActivationAckAttempt : NSObject
@property (nonatomic, assign) int64_t generation;
@property (nonatomic, strong) QONRemoteConfigV2Scope *scope;
@property (nonatomic, strong) QONRemoteConfigV2ActivationAck *ack;
@property (nonatomic, assign) BOOL answered;
@end

@implementation QONRemoteConfigV2ActivationAckAttempt
@end

#pragma mark - Sender

@interface QONRemoteConfigV2ActivationAckSender ()
@property (nonatomic, strong) id<QONRemoteConfigV2AckTransporting> transport;
@property (nonatomic, strong) id<QONRemoteConfigV2ActivationAckStoring> store;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchClock> clock;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchRandom> random;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchScheduler> scheduler;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) NSInteger maximumAttempts;
@property (nonatomic, assign) int64_t initialRetryDelayMilliseconds;
@property (nonatomic, assign) int64_t maximumRetryDelayMilliseconds;

// Everything below is confined to `queue`.
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *boundScope;
@property (nonatomic, strong, nullable) QONRemoteConfigV2ActivationAck *pending;
@property (nonatomic, assign) int64_t settledReleaseNumber;
@property (nonatomic, assign) int64_t generation;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, assign) BOOL retryScheduled;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduledTask> retryTask;
/**
 The retry ladder of one (scope, release), counted for the whole process.

 In memory and keyed by the pair on purpose. The bound on attempts is per
 process, so a rebind — an identify that returns to an identity, a logout and
 back, or the unbind/rebind pair every identity change is made of — must NOT buy
 the same release another ladder against a gateway that is failing. Binding
 fences the in-flight delivery but never the count: only a NEWER release starts
 a new ladder, and only a genuinely new process reads the still-pending record
 and tries again.

 A ladder that reached `maximumAttempts` IS the abandonment: nothing else
 records it, and nothing but a different key clears it.
 */
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *ladderScope;
@property (nonatomic, assign) int64_t ladderReleaseNumber;
@property (nonatomic, assign) NSInteger ladderAttempts;
/** Read from any thread, written on the queue. */
@property (atomic, assign) int64_t droppedAckCount;
@end

@implementation QONRemoteConfigV2ActivationAckSender

- (instancetype)initWithTransport:(id<QONRemoteConfigV2AckTransporting>)transport
                            store:(id<QONRemoteConfigV2ActivationAckStoring>)store
                            clock:(id<QONRemoteConfigV2FetchClock>)clock
                           random:(id<QONRemoteConfigV2FetchRandom>)random
                        scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                            queue:(dispatch_queue_t)queue {
  return [self initWithTransport:transport
                           store:store
                           clock:clock
                          random:random
                       scheduler:scheduler
                           queue:queue
                 maximumAttempts:QONRemoteConfigV2ActivationAckMaximumAttempts
   initialRetryDelayMilliseconds:QONRemoteConfigV2ActivationAckInitialRetryDelayMilliseconds
   maximumRetryDelayMilliseconds:QONRemoteConfigV2ActivationAckMaximumRetryDelayMilliseconds];
}

- (instancetype)initWithTransport:(id<QONRemoteConfigV2AckTransporting>)transport
                            store:(id<QONRemoteConfigV2ActivationAckStoring>)store
                            clock:(id<QONRemoteConfigV2FetchClock>)clock
                           random:(id<QONRemoteConfigV2FetchRandom>)random
                        scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                            queue:(dispatch_queue_t)queue
                  maximumAttempts:(NSInteger)maximumAttempts
    initialRetryDelayMilliseconds:(int64_t)initialRetryDelayMilliseconds
    maximumRetryDelayMilliseconds:(int64_t)maximumRetryDelayMilliseconds {
  if (!transport || !store || !clock || !random || !scheduler || !queue ||
      maximumAttempts < 1 || initialRetryDelayMilliseconds <= 0 ||
      maximumRetryDelayMilliseconds < initialRetryDelayMilliseconds) {
    return nil;
  }
  self = [super init];
  if (self) {
    _transport = transport;
    _store = store;
    _clock = clock;
    _random = random;
    _scheduler = scheduler;
    _queue = queue;
    _maximumAttempts = maximumAttempts;
    _initialRetryDelayMilliseconds = initialRetryDelayMilliseconds;
    _maximumRetryDelayMilliseconds = maximumRetryDelayMilliseconds;
  }
  return self;
}

#pragma mark - Entry points

- (void)bindScope:(QONRemoteConfigV2Scope *)scope {
  dispatch_async(self.queue, ^{
    // Re-binding an identity whose ack is merely still in flight changes
    // nothing: fencing it would re-send an ack whose answer has not arrived, so
    // an identify that does not actually change the identity costs no request.
    if (scope && [scope isEqual:self.boundScope] && (self.inFlight || self.retryScheduled)) {
      return;
    }
    [self invalidateLocked];
    self.boundScope = scope;
    self.pending = nil;
    self.settledReleaseNumber = 0;
    if (scope) {
      QONRemoteConfigV2ActivationAckRecord *record = [self loadRecordForScope:scope];
      self.pending = record.pending;
      self.settledReleaseNumber = record ? record.settledReleaseNumber : 0;
    }
    [self startIfIdleLocked];
  });
}

- (void)recordActivationForScope:(QONRemoteConfigV2Scope *)scope
                   releaseNumber:(int64_t)releaseNumber {
  if (!scope || releaseNumber <= 0) return;
  dispatch_async(self.queue, ^{
    if (![scope isEqual:self.boundScope]) return;
    // Settled is a high-water mark, not a single value: a release at or below
    // it has already been answered for, and re-offering an older one (two reads
    // that raced past each other, say) must not buy it a second ack.
    if (releaseNumber <= self.settledReleaseNumber) return;
    // Newest wins in both directions: an older activation may not supersede a
    // newer queued one, or the newer release — the one actually serving —
    // would be dropped from the queue and from disk.
    if (self.pending && releaseNumber <= self.pending.releaseNumber) return;
    QONRemoteConfigV2ActivationAck *ack = [[QONRemoteConfigV2ActivationAck alloc]
        initWithReleaseNumber:releaseNumber activatedAtSeconds:[self nowSeconds]];
    if (!ack) return;
    self.pending = ack;
    // The newest activation supersedes an older in-flight or scheduled one.
    [self invalidateLocked];
    // Durable BEFORE the first attempt.
    [self flushForScope:scope];
    [self startIfIdleLocked];
  });
}

- (void)settleForTesting {
  dispatch_sync(self.queue, ^{});
}

#pragma mark - Delivery

- (void)startIfIdleLocked {
  QONRemoteConfigV2Scope *scope = self.boundScope;
  QONRemoteConfigV2ActivationAck *ack = self.pending;
  if (!scope || !ack) return;
  if (self.inFlight || self.retryScheduled) return;
  // An exhausted ladder IS the abandonment: a rebind reaches here too, and it
  // may not start over.
  if ([self isLadderFor:scope ack:ack] && self.ladderAttempts >= self.maximumAttempts) return;
  self.inFlight = YES;
  [self dispatchAttemptLocked:scope ack:ack];
}

- (BOOL)isLadderFor:(QONRemoteConfigV2Scope *)scope
                ack:(QONRemoteConfigV2ActivationAck *)ack {
  return [scope isEqual:self.ladderScope] && ack.releaseNumber == self.ladderReleaseNumber;
}

- (void)dispatchAttemptLocked:(QONRemoteConfigV2Scope *)scope
                          ack:(QONRemoteConfigV2ActivationAck *)ack {
  if (![self isLadderFor:scope ack:ack]) {
    self.ladderScope = scope;
    self.ladderReleaseNumber = ack.releaseNumber;
    self.ladderAttempts = 0;
  }
  self.ladderAttempts += 1;
  QONRemoteConfigV2ActivationAckAttempt *attempt = [QONRemoteConfigV2ActivationAckAttempt new];
  attempt.generation = self.generation;
  attempt.scope = scope;
  attempt.ack = ack;
  __weak typeof(self) weakSelf = self;
  @try {
    [self.transport sendAck:ack forScope:scope completion:^(QONRemoteConfigV2AckResponse response) {
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      dispatch_async(strongSelf.queue, ^{
        [strongSelf handleResponse:response forAttempt:attempt];
      });
    }];
  } @catch (__unused NSException *exception) {
    [self handleResponse:QONRemoteConfigV2AckResponseRetryable forAttempt:attempt];
  }
}

- (void)handleResponse:(QONRemoteConfigV2AckResponse)response
            forAttempt:(QONRemoteConfigV2ActivationAckAttempt *)attempt {
  if (attempt.answered) return;
  attempt.answered = YES;
  // A bind or a newer activation happened while this attempt was on the wire:
  // its answer says nothing about the state the sender is in now.
  if (attempt.generation != self.generation || ![attempt.scope isEqual:self.boundScope]) return;
  self.inFlight = NO;
  switch (response) {
    // Both outcomes SETTLE the release durably. A permanent refusal is settled
    // rather than forgotten on purpose: the likeliest one is a gateway that does
    // not serve /ack at all, and forgetting it would re-queue and re-POST the
    // very same ack on every process start and every identity binding, forever.
    case QONRemoteConfigV2AckResponseDelivered:
      [self settleAttempt:attempt];
      return;
    case QONRemoteConfigV2AckResponsePermanent:
      self.droppedAckCount += 1;
      [self settleAttempt:attempt];
      return;
    // Not an attempt: no request was made, so the ladder is refunded and the
    // record stays queued for the identity that owes it.
    case QONRemoteConfigV2AckResponseNotAddressable:
      if ([self isLadderFor:attempt.scope ack:attempt.ack] && self.ladderAttempts > 0) {
        self.ladderAttempts -= 1;
      }
      return;
    case QONRemoteConfigV2AckResponseRetryable:
      if (self.ladderAttempts >= self.maximumAttempts) {
        // Owed but abandoned for this process; the durable record is left
        // untouched so the next process start delivers it, and the ladder is
        // kept so no rebind can start it over.
        self.droppedAckCount += 1;
        return;
      }
      [self scheduleRetryLocked:[self retryDelayMillisecondsForAttempt:self.ladderAttempts]];
      return;
  }
}

- (void)settleAttempt:(QONRemoteConfigV2ActivationAckAttempt *)attempt {
  self.settledReleaseNumber = MAX(self.settledReleaseNumber, attempt.ack.releaseNumber);
  if (self.pending && self.pending.releaseNumber == attempt.ack.releaseNumber) self.pending = nil;
  [self clearLadderLocked];
  [self flushForScope:attempt.scope];
}

/** An answered release owns no ladder: nothing may resume one for it. */
- (void)clearLadderLocked {
  self.ladderScope = nil;
  self.ladderReleaseNumber = 0;
  self.ladderAttempts = 0;
}

- (void)scheduleRetryLocked:(int64_t)delayMilliseconds {
  int64_t scheduledGeneration = self.generation;
  __weak typeof(self) weakSelf = self;
  self.retryScheduled = YES;
  @try {
    self.retryTask = [self.scheduler scheduleAfterMilliseconds:delayMilliseconds action:^{
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      // The timer thread only wakes the sender: the durable read and write of a
      // retry belong on the sender's own queue, never on a shared timer that
      // also releases fetch waiters.
      dispatch_async(strongSelf.queue, ^{
        [strongSelf retryDueForGeneration:scheduledGeneration];
      });
    }];
  } @catch (__unused NSException *exception) {
    self.retryScheduled = NO;
    self.retryTask = nil;
    // A retry that could not even be armed ends the ladder, or the counter
    // would report a drop the state machine still believes is deliverable.
    self.ladderAttempts = self.maximumAttempts;
    self.droppedAckCount += 1;
  }
}

- (void)retryDueForGeneration:(int64_t)scheduledGeneration {
  if (scheduledGeneration != self.generation) return;
  self.retryScheduled = NO;
  self.retryTask = nil;
  QONRemoteConfigV2Scope *scope = self.boundScope;
  QONRemoteConfigV2ActivationAck *ack = self.pending;
  if (!scope || !ack || self.inFlight) return;
  self.inFlight = YES;
  [self dispatchAttemptLocked:scope ack:ack];
}

/**
 Fences everything in flight or scheduled.

 Only the in-memory delivery is invalidated. Neither the durable record nor the
 retry ladder is touched: the ack the record holds is still owed, and the
 attempts already spent on it stay spent for the whole process.
 */
- (void)invalidateLocked {
  self.generation += 1;
  self.retryScheduled = NO;
  id<QONRemoteConfigV2FetchScheduledTask> task = self.retryTask;
  self.retryTask = nil;
  if (task) {
    @try {
      [task cancel];
    } @catch (__unused NSException *exception) {
      // Generation fencing, not cancellation, is what makes a stale timer harmless.
    }
  }
  self.inFlight = NO;
}

- (int64_t)retryDelayMillisecondsForAttempt:(NSInteger)attemptOrdinal {
  int64_t cap = self.initialRetryDelayMilliseconds;
  for (NSInteger index = 1; index < attemptOrdinal; index++) {
    cap = cap >= self.maximumRetryDelayMilliseconds / 2
        ? self.maximumRetryDelayMilliseconds
        : MIN(cap * 2, self.maximumRetryDelayMilliseconds);
  }
  double randomValue = QONRemoteConfigV2ActivationAckSafeJitter;
  @try {
    randomValue = [self.random nextUnitInterval];
  } @catch (__unused NSException *exception) {
    randomValue = QONRemoteConfigV2ActivationAckSafeJitter;
  }
  if (!isfinite(randomValue) || randomValue < 0.0 || randomValue >= 1.0) {
    randomValue = QONRemoteConfigV2ActivationAckSafeJitter;
  }
  // Half the cap plus jitter, not full-downward jitter: the latter can put all
  // three attempts inside a few milliseconds, which is the storm the bound
  // exists to prevent.
  int64_t half = cap / 2;
  int64_t delay = half + (int64_t)((double)half * randomValue);
  return MAX(delay, QONRemoteConfigV2ActivationAckMinimumRetryDelayMilliseconds);
}

#pragma mark - Durability

- (nullable QONRemoteConfigV2ActivationAckRecord *)loadRecordForScope:
    (QONRemoteConfigV2Scope *)scope {
  @try {
    return [self.store recordForScope:scope];
  } @catch (__unused NSException *exception) {
    return nil;
  }
}

- (void)flushForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return;
  @try {
    if (!self.pending && self.settledReleaseNumber <= 0) {
      [self.store removeRecordForScope:scope];
      return;
    }
    QONRemoteConfigV2ActivationAckRecord *record = [[QONRemoteConfigV2ActivationAckRecord alloc]
        initWithPending:self.pending settledReleaseNumber:self.settledReleaseNumber];
    if (record) [self.store storeRecord:record forScope:scope];
  } @catch (__unused NSException *exception) {
    // The in-memory record still governs this process; a lost write can at worst
    // cost one duplicate ack after a restart, which the gateway must tolerate
    // anyway (it upserts per client).
  }
}

/**
 The activation timestamp, floored at 1: a zero would be indistinguishable from
 "absent" in the durable record and would make the queued ack un-persistable.
 */
- (int64_t)nowSeconds {
  int64_t milliseconds = 0;
  @try {
    milliseconds = [self.clock nowMilliseconds];
  } @catch (__unused NSException *exception) {
    milliseconds = 0;
  }
  return MAX(MAX(milliseconds, (int64_t)0) / 1000, (int64_t)1);
}

@end

#pragma mark - Durable store

@interface QONRemoteConfigV2ActivationAckStore ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@end

@implementation QONRemoteConfigV2ActivationAckStore

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  if (!localStorage) return nil;
  self = [super init];
  if (self) _localStorage = localStorage;
  return self;
}

+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2AckAppendFramed(framing,
      [@"remote-config-v2-activation-ack-v1" dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2AckAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2AckAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2AckAppendFramed(framing,
      [scope.canonicalUserID dataUsingEncoding:NSUTF8StringEncoding]);
  return [QONRemoteConfigV2ActivationAckPrefix
      stringByAppendingString:QONRemoteConfigV2AckSHA256(framing)];
}

- (nullable QONRemoteConfigV2ActivationAckRecord *)recordForScope:
    (QONRemoteConfigV2Scope *)scope {
  if (!scope) return nil;
  NSString *key = [QONRemoteConfigV2ActivationAckStore storageKeyForScope:scope];
  @synchronized (self) {
    id object = nil;
    @try {
      object = [self.localStorage loadObjectForKey:key];
    } @catch (__unused NSException *exception) {
      return nil;
    }
    if (![object isKindOfClass:NSDictionary.class]) return nil;

    NSDictionary *dictionary = object;
    int64_t schema = 0;
    int64_t pendingRelease = 0;
    int64_t pendingActivatedAt = 0;
    int64_t settled = 0;
    if (!QONRemoteConfigV2AckExactInt64(dictionary[@"schema_version"], &schema) ||
        schema != QONRemoteConfigV2ActivationAckSchema ||
        !QONRemoteConfigV2AckExactInt64(dictionary[@"pending_release_number"], &pendingRelease) ||
        !QONRemoteConfigV2AckExactInt64(dictionary[@"pending_activated_at"], &pendingActivatedAt) ||
        !QONRemoteConfigV2AckExactInt64(dictionary[@"settled_release_number"], &settled) ||
        ![dictionary[@"scope_key"] isKindOfClass:NSString.class] ||
        ![dictionary[@"scope_key"] isEqualToString:key]) {
      [self removeUnusableKey:key];
      return nil;
    }
    QONRemoteConfigV2ActivationAck *pending = pendingRelease > 0
        ? [[QONRemoteConfigV2ActivationAck alloc] initWithReleaseNumber:pendingRelease
                                                    activatedAtSeconds:pendingActivatedAt]
        : nil;
    // A record that states a pending release it cannot describe is untrusted
    // whole: half of it would silently become "nothing is owed".
    if (pendingRelease > 0 && !pending) {
      [self removeUnusableKey:key];
      return nil;
    }
    QONRemoteConfigV2ActivationAckRecord *record = [[QONRemoteConfigV2ActivationAckRecord alloc]
        initWithPending:pending settledReleaseNumber:settled];
    if (!record) {
      [self removeUnusableKey:key];
      return nil;
    }
    return record;
  }
}

- (BOOL)storeRecord:(QONRemoteConfigV2ActivationAckRecord *)record
           forScope:(QONRemoteConfigV2Scope *)scope {
  if (!record || !scope) return NO;
  NSString *key = [QONRemoteConfigV2ActivationAckStore storageKeyForScope:scope];
  NSDictionary *payload = @{
    @"schema_version": @(QONRemoteConfigV2ActivationAckSchema),
    @"scope_key": key,
    @"pending_release_number": @(record.pending ? record.pending.releaseNumber : 0),
    @"pending_activated_at": @(record.pending ? record.pending.activatedAtSeconds : 0),
    @"settled_release_number": @(record.settledReleaseNumber),
  };
  @synchronized (self) {
    @try {
      [self.localStorage storeObject:payload forKey:key];
      id readBack = [self.localStorage loadObjectForKey:key];
      return [readBack isEqual:payload];
    } @catch (__unused NSException *exception) {
      return NO;
    }
  }
}

- (void)removeRecordForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return;
  @synchronized (self) {
    [self removeUnusableKey:[QONRemoteConfigV2ActivationAckStore storageKeyForScope:scope]];
  }
}

- (void)removeUnusableKey:(NSString *)key {
  @try {
    [self.localStorage removeObjectForKey:key];
  } @catch (__unused NSException *exception) {
    // A malformed record stays untrusted even when best-effort cleanup fails.
  }
}

@end
