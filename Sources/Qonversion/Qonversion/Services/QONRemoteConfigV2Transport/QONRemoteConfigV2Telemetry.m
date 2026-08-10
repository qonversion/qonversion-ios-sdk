#import "QONRemoteConfigV2Telemetry.h"
#import "QNLocalStorage.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

NS_ASSUME_NONNULL_BEGIN

NSInteger const QONRemoteConfigV2TelemetryMaximumAttempts = 3;
int64_t const QONRemoteConfigV2TelemetryInitialRetryDelayMilliseconds = 1000;
int64_t const QONRemoteConfigV2TelemetryMaximumRetryDelayMilliseconds = 30000;
NSUInteger const QONRemoteConfigV2TelemetryMaximumEntries = 64;
NSUInteger const QONRemoteConfigV2TelemetryFlushThreshold = 10;
NSUInteger const QONRemoteConfigV2TelemetryMaximumBatchEntries = 50;
NSUInteger const QONRemoteConfigV2TelemetryMaximumRecordEntries =
    QONRemoteConfigV2TelemetryMaximumEntries + QONRemoteConfigV2TelemetryMaximumBatchEntries;
int64_t const QONRemoteConfigV2TelemetryFlushIntervalMilliseconds = 30000;
int64_t const QONRemoteConfigV2TelemetryMaximumEventCount = 100000;
NSUInteger const QONRemoteConfigV2TelemetryMaximumLogicalKeyBytes = 200;
int64_t const QONRemoteConfigV2TelemetryMaximumEventAgeSeconds = 29 * 24 * 60 * 60;
int64_t const QONRemoteConfigV2TelemetryMaximumClockSkewSeconds = 30;

/**
 The durable record's format version, and the migration lever for it.

 A record written by an older schema is discarded rather than reinterpreted:
 losing a buffer costs a few counters, and telemetry is the one thing in the SDK
 allowed to lose them. Any future change to the stored shape bumps this.
 */
static NSInteger const QONRemoteConfigV2TelemetrySchema = 1;
static NSString *const QONRemoteConfigV2TelemetryPrefix =
    @"com.qonversion.keys.remote-config-v2-telemetry.";
static int64_t const QONRemoteConfigV2TelemetryMinimumRetryDelayMilliseconds = 1;
static double const QONRemoteConfigV2TelemetrySafeJitter = 0.5;

#pragma mark - Shared helpers

static BOOL QONRemoteConfigV2TelemetryExactInt64(id object, int64_t *value) {
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

static void QONRemoteConfigV2TelemetryAppendFramed(NSMutableData *data, NSData *value) {
  uint32_t length = CFSwapInt32HostToBig((uint32_t)value.length);
  [data appendBytes:&length length:sizeof(length)];
  [data appendData:value];
}

static NSString *QONRemoteConfigV2TelemetrySHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return [hex copy];
}

NSString *_Nullable QONRemoteConfigV2TelemetryKindWireName(QONRemoteConfigV2TelemetryKind kind) {
  switch (kind) {
    case QONRemoteConfigV2TelemetryKindDecodeFailure: return @"decode_failure";
    case QONRemoteConfigV2TelemetryKindReadBeforeActivate: return @"read_before_activate";
    case QONRemoteConfigV2TelemetryKindImplicitActivation: return @"implicit_activation";
    case QONRemoteConfigV2TelemetryKindPreloadFailed: return @"preload_failed";
    case QONRemoteConfigV2TelemetryKindPreloadCorrupt: return @"preload_corrupt";
    case QONRemoteConfigV2TelemetryKindActivationPersistenceFailed:
      return @"activation_persistence_failed";
    case QONRemoteConfigV2TelemetryKindSnapshotMalformed: return @"snapshot_malformed";
  }
  return nil;
}

static BOOL QONRemoteConfigV2TelemetryKindFromWireName(NSString *name,
                                                       QONRemoteConfigV2TelemetryKind *kind) {
  if (![name isKindOfClass:NSString.class]) return NO;
  for (NSInteger raw = QONRemoteConfigV2TelemetryKindDecodeFailure;
       raw <= QONRemoteConfigV2TelemetryKindSnapshotMalformed; raw++) {
    NSString *candidate =
        QONRemoteConfigV2TelemetryKindWireName((QONRemoteConfigV2TelemetryKind)raw);
    if ([candidate isEqualToString:name]) {
      if (kind) *kind = (QONRemoteConfigV2TelemetryKind)raw;
      return YES;
    }
  }
  return NO;
}

/**
 The contract's logical-key rule: 1..200 UTF-8 bytes, no control bytes.

 Checked on the client rather than left to the gateway because a single bad key
 makes the server reject the WHOLE batch, taking every well-formed event in it
 down with it.
 */
static BOOL QONRemoteConfigV2TelemetryValidLogicalKey(NSString *_Nullable key) {
  if (![key isKindOfClass:NSString.class] || key.length == 0) return NO;
  NSData *utf8 = [key dataUsingEncoding:NSUTF8StringEncoding];
  if (!utf8 || utf8.length == 0 || utf8.length > QONRemoteConfigV2TelemetryMaximumLogicalKeyBytes) {
    return NO;
  }
  const uint8_t *bytes = utf8.bytes;
  for (NSUInteger index = 0; index < utf8.length; index++) {
    if (bytes[index] < 0x20 || bytes[index] == 0x7f) return NO;
  }
  return YES;
}

/**
 The coalescing identity of an observation: the kind and the key, and
 deliberately NOT the release number.

 The server rejects a batch that names the same (kind, logical_key) twice, and
 it rejects it as a 400 — permanently, taking every other event in that batch
 with it. Keying by the release too would produce exactly that pair whenever a
 release rolled over between two flushes, so the release is carried as an
 attribute of the entry rather than as part of its identity.
 */
static NSString *QONRemoteConfigV2TelemetryMapKey(QONRemoteConfigV2TelemetryKind kind,
                                                  NSString *_Nullable logicalKey) {
  return [NSString stringWithFormat:@"%ld\n%@", (long)kind, logicalKey ?: @""];
}

/** What folding an observation into the map actually did. */
typedef NS_ENUM(NSInteger, QONRemoteConfigV2TelemetryMergeOutcome) {
  QONRemoteConfigV2TelemetryMergeOutcomeDropped,
  /** A new entry appeared, so the shape of the buffer changed. */
  QONRemoteConfigV2TelemetryMergeOutcomeCreated,
  /** An existing entry's counter moved, and nothing else did. */
  QONRemoteConfigV2TelemetryMergeOutcomeCounted,
};

#pragma mark - Model

@implementation QONRemoteConfigV2TelemetryEvent

- (nullable instancetype)initWithKind:(QONRemoteConfigV2TelemetryKind)kind
                               logicalKey:(nullable NSString *)logicalKey
                releaseNumber:(int64_t)releaseNumber
                        count:(int64_t)count
        lastOccurredAtSeconds:(int64_t)lastOccurredAtSeconds {
  if (!QONRemoteConfigV2TelemetryKindWireName(kind)) return nil;
  // The key rule is an iff, in both directions: the gateway rejects a batch that
  // names a key on a keyless kind just as firmly as one that omits it on
  // decode_failure.
  BOOL requiresLogicalKey = kind == QONRemoteConfigV2TelemetryKindDecodeFailure;
  if (requiresLogicalKey && !QONRemoteConfigV2TelemetryValidLogicalKey(logicalKey)) return nil;
  if (!requiresLogicalKey && logicalKey != nil) return nil;
  if (releaseNumber < 0 || releaseNumber > QONRemoteConfigV2MaximumSafeInteger) return nil;
  if (count < 1 || count > QONRemoteConfigV2TelemetryMaximumEventCount) return nil;
  // A zero timestamp would be indistinguishable from "absent" in the durable
  // record and would make the buffered event silently un-persistable.
  if (lastOccurredAtSeconds <= 0 ||
      lastOccurredAtSeconds > QONRemoteConfigV2MaximumSafeInteger) return nil;
  self = [super init];
  if (self) {
    _kind = kind;
    _logicalKey = [logicalKey copy];
    _releaseNumber = releaseNumber;
    _count = count;
    _lastOccurredAtSeconds = lastOccurredAtSeconds;
  }
  return self;
}

- (id)copyWithZone:(nullable __unused NSZone *)zone {
  return self;
}

- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2TelemetryEvent.class]) return NO;
  QONRemoteConfigV2TelemetryEvent *other = object;
  BOOL sameKey = (self.logicalKey == nil && other.logicalKey == nil) ||
      [self.logicalKey isEqualToString:other.logicalKey];
  return self.kind == other.kind && sameKey && self.releaseNumber == other.releaseNumber &&
      self.count == other.count && self.lastOccurredAtSeconds == other.lastOccurredAtSeconds;
}

- (NSUInteger)hash {
  return (NSUInteger)((int64_t)self.kind ^ self.releaseNumber ^ self.count) ^ self.logicalKey.hash;
}

- (nullable NSDictionary<NSString *, id> *)JSONObject {
  NSString *name = QONRemoteConfigV2TelemetryKindWireName(self.kind);
  if (!name) return nil;
  NSMutableDictionary<NSString *, id> *object = [NSMutableDictionary dictionaryWithCapacity:5];
  object[@"kind"] = name;
  object[@"release_number"] = @(self.releaseNumber);
  object[@"count"] = @(self.count);
  object[@"last_occurred_at"] = @(self.lastOccurredAtSeconds);
  // Present iff decode_failure, which the initializer already guarantees.
  if (self.logicalKey) object[@"logical_key"] = self.logicalKey;
  return [object copy];
}

@end

@implementation QONRemoteConfigV2TelemetryRecord

- (nullable instancetype)initWithEvents:(NSArray<QONRemoteConfigV2TelemetryEvent *> *)events {
  if (![events isKindOfClass:NSArray.class]) return nil;
  for (id event in events) {
    if (![event isKindOfClass:QONRemoteConfigV2TelemetryEvent.class]) return nil;
  }
  self = [super init];
  if (self) _events = [events copy];
  return self;
}

- (id)copyWithZone:(nullable __unused NSZone *)zone {
  return self;
}

@end

#pragma mark - Attempt

/**
 One flush attempt.

 `answered` makes the completion single-shot independently of the transport: a
 transport that both calls back and throws must not advance the retry budget
 twice. It is only ever touched on the sender's queue.
 */
@interface QONRemoteConfigV2TelemetryAttempt : NSObject
@property (nonatomic, assign) int64_t generation;
@property (nonatomic, strong) QONRemoteConfigV2Scope *scope;
@property (nonatomic, assign) BOOL answered;
@end

@implementation QONRemoteConfigV2TelemetryAttempt
@end

#pragma mark - Sender

@interface QONRemoteConfigV2TelemetrySender ()
@property (nonatomic, strong) id<QONRemoteConfigV2TelemetryTransporting> transport;
@property (nonatomic, strong) id<QONRemoteConfigV2TelemetryStoring> store;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchClock> clock;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchRandom> random;
@property (nonatomic, strong) id<QONRemoteConfigV2FetchScheduler> scheduler;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) NSInteger maximumAttempts;
@property (nonatomic, assign) int64_t initialRetryDelayMilliseconds;
@property (nonatomic, assign) int64_t maximumRetryDelayMilliseconds;
@property (nonatomic, assign) NSUInteger maximumEntries;
@property (nonatomic, assign) NSUInteger flushThreshold;
@property (nonatomic, assign) int64_t flushIntervalMilliseconds;

// Everything below is confined to `queue`.
@property (nonatomic, strong, nullable) QONRemoteConfigV2Scope *boundScope;
/** The coalescing map: map key -> the single event that stands for all of them. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigV2TelemetryEvent *> *entries;
/** Insertion order of `entries`, so a batch is always the oldest observations. */
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
/** The batch handed to the transport, still durable until it settles. */
@property (nonatomic, copy, nullable) NSArray<QONRemoteConfigV2TelemetryEvent *> *batch;
@property (nonatomic, assign) NSInteger batchAttempts;
@property (nonatomic, assign) int64_t generation;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, assign) BOOL retryScheduled;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduledTask> retryTask;
@property (nonatomic, assign) BOOL tickScheduled;
@property (nonatomic, strong, nullable) id<QONRemoteConfigV2FetchScheduledTask> tickTask;
/**
 A counter moved, or a write was refused, and the disk does not know yet.

 Set by the cheap path that deliberately skips storage, and cleared only by a
 write the store confirmed. The periodic tick is what settles it.
 */
@property (nonatomic, assign) BOOL pendingPersist;
/** Read from any thread, written on the queue. */
@property (atomic, assign) int64_t droppedEventCount;
@end

@implementation QONRemoteConfigV2TelemetrySender

- (nullable instancetype)initWithTransport:(id<QONRemoteConfigV2TelemetryTransporting>)transport
                            store:(id<QONRemoteConfigV2TelemetryStoring>)store
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
                 maximumAttempts:QONRemoteConfigV2TelemetryMaximumAttempts
   initialRetryDelayMilliseconds:QONRemoteConfigV2TelemetryInitialRetryDelayMilliseconds
   maximumRetryDelayMilliseconds:QONRemoteConfigV2TelemetryMaximumRetryDelayMilliseconds
                  maximumEntries:QONRemoteConfigV2TelemetryMaximumEntries
                  flushThreshold:QONRemoteConfigV2TelemetryFlushThreshold
       flushIntervalMilliseconds:QONRemoteConfigV2TelemetryFlushIntervalMilliseconds];
}

- (nullable instancetype)initWithTransport:(id<QONRemoteConfigV2TelemetryTransporting>)transport
                            store:(id<QONRemoteConfigV2TelemetryStoring>)store
                            clock:(id<QONRemoteConfigV2FetchClock>)clock
                           random:(id<QONRemoteConfigV2FetchRandom>)random
                        scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                            queue:(dispatch_queue_t)queue
                  maximumAttempts:(NSInteger)maximumAttempts
    initialRetryDelayMilliseconds:(int64_t)initialRetryDelayMilliseconds
    maximumRetryDelayMilliseconds:(int64_t)maximumRetryDelayMilliseconds
                   maximumEntries:(NSUInteger)maximumEntries
                   flushThreshold:(NSUInteger)flushThreshold
        flushIntervalMilliseconds:(int64_t)flushIntervalMilliseconds {
  if (!transport || !store || !clock || !random || !scheduler || !queue ||
      maximumAttempts < 1 || initialRetryDelayMilliseconds <= 0 ||
      maximumRetryDelayMilliseconds < initialRetryDelayMilliseconds ||
      maximumEntries < 1 || flushThreshold < 1 || flushIntervalMilliseconds <= 0) {
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
    _maximumEntries = maximumEntries;
    _flushThreshold = flushThreshold;
    _flushIntervalMilliseconds = flushIntervalMilliseconds;
    _entries = [NSMutableDictionary new];
    _order = [NSMutableArray new];
  }
  return self;
}

#pragma mark - Entry points

- (void)bindScope:(nullable QONRemoteConfigV2Scope *)scope {
  dispatch_async(self.queue, ^{
    // Re-binding an identity whose batch is merely still in flight changes
    // nothing: fencing it would re-send events whose answer has not arrived, and
    // the server adds counts rather than replacing them, so the re-send would
    // double-count.
    if (scope && [scope isEqual:self.boundScope] && (self.inFlight || self.retryScheduled)) {
      return;
    }
    [self invalidateLocked];
    self.boundScope = scope;
    self.batch = nil;
    self.batchAttempts = 0;
    [self.entries removeAllObjects];
    [self.order removeAllObjects];
    if (scope) {
      QONRemoteConfigV2TelemetryRecord *record = [self loadRecordForScope:scope];
      for (QONRemoteConfigV2TelemetryEvent *event in record.events) {
        // Restoring is the one merge that may exceed the map's own bound: the
        // record legitimately holds a batch plus a map, and refusing half of it
        // here would throw away what the previous process paid to keep.
        [self mergeEventLocked:event allowingOverflow:YES];
      }
      // Only when the buffer on disk did not survive the read unchanged —
      // because it overflowed even the record bound, or because it was written
      // by a build that keyed entries by the release too and now collapses.
      // Rewriting it here is what stops the same work being redone every bind.
      if (self.entries.count != record.events.count) [self persistLocked];
    }
    [self startIfDueLocked];
  });
}

- (void)recordKind:(QONRemoteConfigV2TelemetryKind)kind
        logicalKey:(nullable NSString *)logicalKey
     releaseNumber:(int64_t)releaseNumber {
  // Copied here, on the caller's thread, so a mutable string handed in from a
  // read cannot change underneath the queue.
  NSString *_Nullable key = [logicalKey copy];
  dispatch_async(self.queue, ^{
    [self ingestKind:kind logicalKey:key releaseNumber:releaseNumber];
  });
}

- (void)noteSuccessfulFetch {
  dispatch_async(self.queue, ^{
    [self flushLocked];
  });
}

- (void)settleForTesting {
  dispatch_sync(self.queue, ^{});
}

#pragma mark - Collection

- (void)ingestKind:(QONRemoteConfigV2TelemetryKind)kind
        logicalKey:(nullable NSString *)logicalKey
     releaseNumber:(int64_t)releaseNumber {
  QONRemoteConfigV2Scope *scope = self.boundScope;
  // Nothing to attribute an observation to. Buffering it for the next identity
  // would be worse than dropping it: it would report one identity's fault under
  // another identity's session.
  if (!scope) return;
  QONRemoteConfigV2TelemetryEvent *observation = [[QONRemoteConfigV2TelemetryEvent alloc]
      initWithKind:kind
        logicalKey:logicalKey
     releaseNumber:releaseNumber
             count:1
lastOccurredAtSeconds:[self nowSeconds]];
  if (!observation) {
    // An observation the contract refuses is dropped here rather than sent:
    // one malformed event makes the gateway reject the whole batch it lands in.
    self.droppedEventCount += 1;
    return;
  }
  QONRemoteConfigV2TelemetryMergeOutcome outcome =
      [self mergeEventLocked:observation allowingOverflow:NO];
  if (outcome == QONRemoteConfigV2TelemetryMergeOutcomeDropped) return;
  if (outcome == QONRemoteConfigV2TelemetryMergeOutcomeCreated) {
    // A new entry changes what the buffer IS, and that is worth a disk write.
    [self persistLocked];
  } else {
    // A counter bump is not. This method runs behind an app read — a screen
    // that decodes twenty keys it cannot parse would otherwise pay twenty
    // storage round trips — and the crash that loses a few increments loses
    // exactly the kind of thing telemetry is allowed to lose. The tick below
    // writes them out on its own schedule instead.
    self.pendingPersist = YES;
  }
  [self startIfDueLocked];
}

/**
 Folds one event into the coalescing map and says what that did.

 This is the whole bound: repeated failure of the same thing costs one map entry
 and an increment, never a new record. A brand-new key beyond `maximumEntries`
 is dropped rather than admitted, so the buffer cannot grow without limit even
 under an app that decodes a fresh random key on every read.

 A release rollover folds into the same entry rather than starting a second one:
 the counts add up and the entry takes the NEWEST release number, because the
 dashboard asks "which release are clients failing on now", and because two
 entries would be the duplicate pair the gateway rejects the whole batch for.

 `allowOverflow` is for the two merges that are not new information — restoring
 the durable buffer and taking an unsent batch back — where refusing to exceed
 the map's bound would silently destroy events the sender already owns. Both are
 still bounded, at `maximumEntries` plus one batch, because a batch is capped.
 */
- (QONRemoteConfigV2TelemetryMergeOutcome)mergeEventLocked:
    (QONRemoteConfigV2TelemetryEvent *)event
                                          allowingOverflow:(BOOL)allowOverflow {
  if (!event) return QONRemoteConfigV2TelemetryMergeOutcomeDropped;
  NSString *mapKey = QONRemoteConfigV2TelemetryMapKey(event.kind, event.logicalKey);
  QONRemoteConfigV2TelemetryEvent *existing = self.entries[mapKey];
  if (!existing) {
    if (!allowOverflow && self.entries.count >= self.maximumEntries) {
      self.droppedEventCount += event.count;
      return QONRemoteConfigV2TelemetryMergeOutcomeDropped;
    }
    self.entries[mapKey] = event;
    [self.order addObject:mapKey];
    return QONRemoteConfigV2TelemetryMergeOutcomeCreated;
  }
  int64_t merged = existing.count;
  int64_t room = QONRemoteConfigV2TelemetryMaximumEventCount - existing.count;
  if (event.count > room) {
    // Saturating rather than wrapping or growing: the contract caps `count`, and
    // an app that produced a hundred thousand of one event has already said
    // everything the dashboard needs to hear.
    self.droppedEventCount += event.count - room;
    merged = QONRemoteConfigV2TelemetryMaximumEventCount;
  } else {
    merged += event.count;
  }
  QONRemoteConfigV2TelemetryEvent *newer = [self newerOf:existing and:event];
  QONRemoteConfigV2TelemetryEvent *coalesced = [[QONRemoteConfigV2TelemetryEvent alloc]
      initWithKind:existing.kind
        logicalKey:existing.logicalKey
     releaseNumber:newer.releaseNumber
             count:merged
lastOccurredAtSeconds:MAX(existing.lastOccurredAtSeconds, event.lastOccurredAtSeconds)];
  if (coalesced) self.entries[mapKey] = coalesced;
  return QONRemoteConfigV2TelemetryMergeOutcomeCounted;
}

/**
 Which of two observations of the same (kind, key) is the newer one.

 Normally the later timestamp decides. A tie is broken by the higher release
 number rather than by arrival order, because release numbers only ever grow and
 because merges happen in two different orders — a fresh observation folding
 into the map, and an unsent batch folding back into it — which must not be able
 to disagree about the same pair of events.
 */
- (QONRemoteConfigV2TelemetryEvent *)newerOf:(QONRemoteConfigV2TelemetryEvent *)left
                                          and:(QONRemoteConfigV2TelemetryEvent *)right {
  if (left.lastOccurredAtSeconds != right.lastOccurredAtSeconds) {
    return left.lastOccurredAtSeconds > right.lastOccurredAtSeconds ? left : right;
  }
  return left.releaseNumber >= right.releaseNumber ? left : right;
}

#pragma mark - Delivery

/** Starts a flush when one is due, and otherwise makes sure the tick is armed. */
- (void)startIfDueLocked {
  if (self.batch || self.entries.count >= self.flushThreshold) {
    [self flushLocked];
    return;
  }
  [self armTickLocked];
}

- (void)flushLocked {
  QONRemoteConfigV2Scope *scope = self.boundScope;
  if (!scope) return;
  // Exactly one flush is ever in flight: a second one would race the first for
  // the same events and the server would count them twice.
  if (self.inFlight || self.retryScheduled) return;
  if (!self.batch) {
    if (self.order.count == 0) return;
    int64_t now = [self nowSecondsOrZero];
    if (now <= 0) {
      // The clock seam is unusable, so every timestamp a batch could carry would
      // be the epoch floor — which the server refuses as a 400, permanently, for
      // the whole batch. Waiting costs nothing; sending costs everything in it.
      [self armTickLocked];
      return;
    }
    NSUInteger take = MIN(self.order.count, QONRemoteConfigV2TelemetryMaximumBatchEntries);
    NSMutableArray<QONRemoteConfigV2TelemetryEvent *> *batch =
        [NSMutableArray arrayWithCapacity:take];
    for (NSUInteger index = 0; index < take; index++) {
      NSString *mapKey = self.order[index];
      QONRemoteConfigV2TelemetryEvent *event = self.entries[mapKey];
      [self.entries removeObjectForKey:mapKey];
      if (!event) continue;
      if ([self isStaleLocked:event now:now]) {
        // One event a restored buffer carried from a month ago, or from a clock
        // that has since been corrected backwards, would take every fresh event
        // shipped beside it down with it. Dropping it is the cheap half.
        self.droppedEventCount += event.count;
        continue;
      }
      [batch addObject:event];
    }
    [self.order removeObjectsInRange:NSMakeRange(0, take)];
    if (batch.count == 0) {
      // Everything taken was stale: the buffer shrank and nothing goes out.
      [self persistLocked];
      [self armTickLocked];
      return;
    }
    self.batch = batch;
    self.batchAttempts = 0;
    // Durable BEFORE the first attempt, and the batch stays in the record while
    // it is in flight: a process death mid-flush must not lose it.
    [self persistLocked];
  }
  [self cancelTickLocked];
  self.inFlight = YES;
  [self dispatchAttemptLocked:scope];
}

/** Outside the window the server accepts, with a day of margin on the old side. */
- (BOOL)isStaleLocked:(QONRemoteConfigV2TelemetryEvent *)event now:(int64_t)now {
  if (event.lastOccurredAtSeconds > now + QONRemoteConfigV2TelemetryMaximumClockSkewSeconds) {
    return YES;
  }
  return event.lastOccurredAtSeconds < now - QONRemoteConfigV2TelemetryMaximumEventAgeSeconds;
}

- (void)dispatchAttemptLocked:(QONRemoteConfigV2Scope *)scope {
  NSArray<QONRemoteConfigV2TelemetryEvent *> *batch = self.batch;
  if (!batch.count) {
    self.inFlight = NO;
    return;
  }
  self.batchAttempts += 1;
  QONRemoteConfigV2TelemetryAttempt *attempt = [QONRemoteConfigV2TelemetryAttempt new];
  attempt.generation = self.generation;
  attempt.scope = scope;
  __weak typeof(self) weakSelf = self;
  @try {
    [self.transport sendTelemetryBatch:batch
                              forScope:scope
                            completion:^(QONRemoteConfigV2TelemetryResponse response) {
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      dispatch_async(strongSelf.queue, ^{
        [strongSelf handleResponse:response forAttempt:attempt];
      });
    }];
  } @catch (__unused NSException *exception) {
    [self handleResponse:QONRemoteConfigV2TelemetryResponseRetryable forAttempt:attempt];
  }
}

- (void)handleResponse:(QONRemoteConfigV2TelemetryResponse)response
            forAttempt:(QONRemoteConfigV2TelemetryAttempt *)attempt {
  if (attempt.answered) return;
  attempt.answered = YES;
  // A bind happened while this attempt was on the wire: its answer says nothing
  // about the state the sender is in now.
  if (attempt.generation != self.generation || ![attempt.scope isEqual:self.boundScope]) return;
  self.inFlight = NO;
  switch (response) {
    case QONRemoteConfigV2TelemetryResponseDelivered:
      [self settleBatchLockedDropped:NO];
      return;
    // A 400-family answer is the gateway saying these exact bytes are
    // unacceptable. Re-sending them can only produce the same refusal, and the
    // contract makes dropping mandatory rather than merely allowed.
    case QONRemoteConfigV2TelemetryResponsePermanent:
      [self settleBatchLockedDropped:YES];
      return;
    // Not an attempt: no request was made, so the ladder is refunded and the
    // events go back into the map for the identity that owns them.
    case QONRemoteConfigV2TelemetryResponseNotAddressable:
      if (self.batchAttempts > 0) self.batchAttempts -= 1;
      [self returnBatchLocked];
      [self armTickLocked];
      return;
    case QONRemoteConfigV2TelemetryResponseRetryable:
      if (self.batchAttempts >= self.maximumAttempts) {
        // Bounded on purpose: telemetry may never turn a failing gateway into a
        // request storm, and it may never grow the buffer waiting for one.
        [self settleBatchLockedDropped:YES];
        return;
      }
      [self scheduleRetryLocked:[self retryDelayMillisecondsForAttempt:self.batchAttempts]];
      return;
  }
}

- (void)settleBatchLockedDropped:(BOOL)dropped {
  if (dropped) {
    for (QONRemoteConfigV2TelemetryEvent *event in self.batch) {
      self.droppedEventCount += event.count;
    }
  }
  self.batch = nil;
  self.batchAttempts = 0;
  [self persistLocked];
  // Whatever accumulated while the batch was on the wire may already be due.
  if (self.entries.count >= self.flushThreshold) {
    [self flushLocked];
    return;
  }
  [self armTickLocked];
}

/**
 Folds an unsent batch back into the map.

 Re-merged rather than re-prepended: an entry that grew while the batch was out
 must keep both counts, and the map is the only place that can add them. A key
 that is no longer in the map re-enters it at the TAIL, so the order is not the
 original one — which costs nothing, because a batch is a set of distinct
 entries and the server upserts each one independently.

 The map's bound is deliberately bypassed here. These events were already
 accepted, already counted and already durable; refusing them now would drop
 data the sender owns because of a limit meant to stop it acquiring more.
 */
- (void)returnBatchLocked {
  NSArray<QONRemoteConfigV2TelemetryEvent *> *batch = self.batch;
  self.batch = nil;
  if (!batch.count) return;
  for (QONRemoteConfigV2TelemetryEvent *event in batch) {
    [self mergeEventLocked:event allowingOverflow:YES];
  }
  [self persistLocked];
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
      // retry belong on the sender's own queue.
      dispatch_async(strongSelf.queue, ^{
        [strongSelf retryDueForGeneration:scheduledGeneration];
      });
    }];
  } @catch (__unused NSException *exception) {
    self.retryScheduled = NO;
    self.retryTask = nil;
    // A retry that could not even be armed ends the ladder, or the batch would
    // stay durable forever with nothing left to move it.
    self.batchAttempts = self.maximumAttempts;
    [self settleBatchLockedDropped:YES];
  }
}

- (void)retryDueForGeneration:(int64_t)scheduledGeneration {
  if (scheduledGeneration != self.generation) return;
  self.retryScheduled = NO;
  self.retryTask = nil;
  QONRemoteConfigV2Scope *scope = self.boundScope;
  if (!scope || !self.batch.count || self.inFlight) return;
  self.inFlight = YES;
  [self dispatchAttemptLocked:scope];
}

#pragma mark - Periodic tick

/**
 Arms the flush tick, which is what makes a handful of events reach the server
 at all: without it a buffer that never grows to `flushThreshold` would sit on
 disk until the next successful fetch, and an app that never fetches again would
 never report anything.
 */
- (void)armTickLocked {
  if (self.tickScheduled || self.inFlight || self.retryScheduled) return;
  if (!self.boundScope || (self.entries.count == 0 && !self.batch)) return;
  int64_t scheduledGeneration = self.generation;
  __weak typeof(self) weakSelf = self;
  self.tickScheduled = YES;
  @try {
    self.tickTask = [self.scheduler scheduleAfterMilliseconds:self.flushIntervalMilliseconds
                                                       action:^{
      typeof(self) strongSelf = weakSelf;
      if (!strongSelf) return;
      dispatch_async(strongSelf.queue, ^{
        [strongSelf tickDueForGeneration:scheduledGeneration];
      });
    }];
  } @catch (__unused NSException *exception) {
    self.tickScheduled = NO;
    self.tickTask = nil;
    // No tick means the buffer waits for a threshold or a fetch. It stays
    // durable and bounded either way, so this is a delay, never a leak.
  }
}

- (void)tickDueForGeneration:(int64_t)scheduledGeneration {
  if (scheduledGeneration != self.generation) return;
  self.tickScheduled = NO;
  self.tickTask = nil;
  // The counter bumps that skipped their disk write are settled here, on a
  // timer, rather than on the read path that produced them.
  if (self.pendingPersist) [self persistLocked];
  [self flushLocked];
}

- (void)cancelTickLocked {
  self.tickScheduled = NO;
  id<QONRemoteConfigV2FetchScheduledTask> task = self.tickTask;
  self.tickTask = nil;
  if (!task) return;
  @try {
    [task cancel];
  } @catch (__unused NSException *exception) {
    // Generation fencing, not cancellation, is what makes a stale timer harmless.
  }
}

/**
 Fences everything in flight or scheduled.

 Only the in-memory delivery is invalidated. The durable record is left exactly
 as it is: the events it holds are still owed by the identity that produced
 them, and the next binding of that identity is what resumes them.
 */
- (void)invalidateLocked {
  self.generation += 1;
  self.retryScheduled = NO;
  id<QONRemoteConfigV2FetchScheduledTask> retry = self.retryTask;
  self.retryTask = nil;
  if (retry) {
    @try {
      [retry cancel];
    } @catch (__unused NSException *exception) {}
  }
  [self cancelTickLocked];
  self.inFlight = NO;
}

- (int64_t)retryDelayMillisecondsForAttempt:(NSInteger)attemptOrdinal {
  int64_t cap = self.initialRetryDelayMilliseconds;
  for (NSInteger index = 1; index < attemptOrdinal; index++) {
    cap = cap >= self.maximumRetryDelayMilliseconds / 2
        ? self.maximumRetryDelayMilliseconds
        : MIN(cap * 2, self.maximumRetryDelayMilliseconds);
  }
  double randomValue = QONRemoteConfigV2TelemetrySafeJitter;
  @try {
    randomValue = [self.random nextUnitInterval];
  } @catch (__unused NSException *exception) {
    randomValue = QONRemoteConfigV2TelemetrySafeJitter;
  }
  if (!isfinite(randomValue) || randomValue < 0.0 || randomValue >= 1.0) {
    randomValue = QONRemoteConfigV2TelemetrySafeJitter;
  }
  // Half the cap plus jitter, not full-downward jitter: the latter can put every
  // attempt inside a few milliseconds, which is the storm the bound exists to
  // prevent.
  int64_t half = cap / 2;
  int64_t delay = half + (int64_t)((double)half * randomValue);
  return MAX(delay, QONRemoteConfigV2TelemetryMinimumRetryDelayMilliseconds);
}

#pragma mark - Durability

- (nullable QONRemoteConfigV2TelemetryRecord *)loadRecordForScope:
    (QONRemoteConfigV2Scope *)scope {
  @try {
    return [self.store recordForScope:scope];
  } @catch (__unused NSException *exception) {
    return nil;
  }
}

/**
 The whole buffer: the batch on the wire first, then the map in its own order.

 The record therefore holds up to one batch plus the map, which is exactly what
 QONRemoteConfigV2TelemetryMaximumRecordEntries is sized for. A refused or
 failed write is swallowed — but the pending-write flag is only cleared when the
 store actually took it, so the next tick tries again rather than assuming the
 disk agrees with memory.
 */
- (void)persistLocked {
  QONRemoteConfigV2Scope *scope = self.boundScope;
  if (!scope) return;
  @try {
    NSMutableArray<QONRemoteConfigV2TelemetryEvent *> *events = [NSMutableArray new];
    [events addObjectsFromArray:self.batch ?: @[]];
    for (NSString *mapKey in self.order) {
      QONRemoteConfigV2TelemetryEvent *event = self.entries[mapKey];
      if (event) [events addObject:event];
    }
    if (events.count == 0) {
      [self.store removeRecordForScope:scope];
      self.pendingPersist = NO;
      return;
    }
    QONRemoteConfigV2TelemetryRecord *record =
        [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:events];
    self.pendingPersist = !(record && [self.store storeRecord:record forScope:scope]);
  } @catch (__unused NSException *exception) {
    // The in-memory buffer still governs this process; a lost write can at worst
    // cost a restart's worth of telemetry, which is exactly what telemetry is
    // allowed to lose.
    self.pendingPersist = YES;
  }
}

/** The clock in whole seconds, or 0 when the seam gave nothing usable. */
- (int64_t)nowSecondsOrZero {
  int64_t milliseconds = 0;
  @try {
    milliseconds = [self.clock nowMilliseconds];
  } @catch (__unused NSException *exception) {
    milliseconds = 0;
  }
  return milliseconds > 0 ? milliseconds / 1000 : 0;
}

/**
 The observation timestamp, floored at 1: a zero would be indistinguishable from
 "absent" in the durable record and would make the event un-persistable.

 An event stamped with that floor is unsendable — the flush guard refuses to
 build a batch at all while the clock is unusable — but it is still worth
 buffering, because a clock that comes back gives the count somewhere to go.
 */
- (int64_t)nowSeconds {
  return MAX([self nowSecondsOrZero], (int64_t)1);
}

@end

#pragma mark - Durable store

@interface QONRemoteConfigV2TelemetryStore ()
@property (nonatomic, strong) id<QNLocalStorage> localStorage;
@end

@implementation QONRemoteConfigV2TelemetryStore

- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  if (!localStorage) return nil;
  self = [super init];
  if (self) _localStorage = localStorage;
  return self;
}

+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope {
  NSMutableData *framing = [NSMutableData new];
  QONRemoteConfigV2TelemetryAppendFramed(framing,
      [@"remote-config-v2-client-telemetry-v1" dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2TelemetryAppendFramed(framing,
      [scope.projectKey dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2TelemetryAppendFramed(framing,
      [scope.environment dataUsingEncoding:NSUTF8StringEncoding]);
  QONRemoteConfigV2TelemetryAppendFramed(framing,
      [scope.canonicalUserID dataUsingEncoding:NSUTF8StringEncoding]);
  return [QONRemoteConfigV2TelemetryPrefix
      stringByAppendingString:QONRemoteConfigV2TelemetrySHA256(framing)];
}

- (nullable QONRemoteConfigV2TelemetryRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope {
  if (!scope) return nil;
  NSString *key = [QONRemoteConfigV2TelemetryStore storageKeyForScope:scope];
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
    if (!QONRemoteConfigV2TelemetryExactInt64(dictionary[@"schema_version"], &schema) ||
        schema != QONRemoteConfigV2TelemetrySchema ||
        ![dictionary[@"scope_key"] isKindOfClass:NSString.class] ||
        ![dictionary[@"scope_key"] isEqualToString:key] ||
        ![dictionary[@"events"] isKindOfClass:NSArray.class]) {
      [self removeUnusableKey:key];
      return nil;
    }

    NSArray *rawEvents = dictionary[@"events"];
    if (rawEvents.count > QONRemoteConfigV2TelemetryMaximumRecordEntries) {
      [self removeUnusableKey:key];
      return nil;
    }
    NSMutableArray<QONRemoteConfigV2TelemetryEvent *> *events =
        [NSMutableArray arrayWithCapacity:rawEvents.count];
    for (id rawEvent in rawEvents) {
      QONRemoteConfigV2TelemetryEvent *event = [self eventFromObject:rawEvent];
      // A buffer that states an event it cannot describe is untrusted whole:
      // keeping the readable half would silently under-report the rest.
      if (!event) {
        [self removeUnusableKey:key];
        return nil;
      }
      [events addObject:event];
    }
    QONRemoteConfigV2TelemetryRecord *record =
        [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:events];
    if (!record) {
      [self removeUnusableKey:key];
      return nil;
    }
    return record;
  }
}

- (nullable QONRemoteConfigV2TelemetryEvent *)eventFromObject:(id)object {
  if (![object isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *dictionary = object;
  QONRemoteConfigV2TelemetryKind kind = QONRemoteConfigV2TelemetryKindDecodeFailure;
  int64_t releaseNumber = 0;
  int64_t count = 0;
  int64_t lastOccurredAt = 0;
  if (!QONRemoteConfigV2TelemetryKindFromWireName(dictionary[@"kind"], &kind) ||
      !QONRemoteConfigV2TelemetryExactInt64(dictionary[@"release_number"], &releaseNumber) ||
      !QONRemoteConfigV2TelemetryExactInt64(dictionary[@"count"], &count) ||
      !QONRemoteConfigV2TelemetryExactInt64(dictionary[@"last_occurred_at"], &lastOccurredAt)) {
    return nil;
  }
  id logicalKey = dictionary[@"logical_key"];
  if (logicalKey != nil && ![logicalKey isKindOfClass:NSString.class]) return nil;
  return [[QONRemoteConfigV2TelemetryEvent alloc] initWithKind:kind
                                                    logicalKey:logicalKey
                                                 releaseNumber:releaseNumber
                                                         count:count
                                         lastOccurredAtSeconds:lastOccurredAt];
}

- (BOOL)storeRecord:(QONRemoteConfigV2TelemetryRecord *)record
           forScope:(QONRemoteConfigV2Scope *)scope {
  if (!record || !scope) return NO;
  if (record.events.count > QONRemoteConfigV2TelemetryMaximumRecordEntries) return NO;
  NSString *key = [QONRemoteConfigV2TelemetryStore storageKeyForScope:scope];
  NSMutableArray<NSDictionary<NSString *, id> *> *events =
      [NSMutableArray arrayWithCapacity:record.events.count];
  for (QONRemoteConfigV2TelemetryEvent *event in record.events) {
    NSDictionary<NSString *, id> *object = [event JSONObject];
    if (!object) return NO;
    [events addObject:object];
  }
  NSDictionary *payload = @{
    @"schema_version": @(QONRemoteConfigV2TelemetrySchema),
    @"scope_key": key,
    @"events": [events copy],
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
    [self removeUnusableKey:[QONRemoteConfigV2TelemetryStore storageKeyForScope:scope]];
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

NS_ASSUME_NONNULL_END
