#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2Models.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSInteger const QONRemoteConfigV2TelemetryMaximumAttempts;
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2TelemetryInitialRetryDelayMilliseconds;
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2TelemetryMaximumRetryDelayMilliseconds;
/** The coalescing map never holds more distinct entries than this. */
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2TelemetryMaximumEntries;
/** Distinct entries that make a flush due on their own. */
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2TelemetryFlushThreshold;
/** The wire contract caps one request at this many events. */
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2TelemetryMaximumBatchEntries;
/**
 The durable buffer's own cap: the map at its bound PLUS a full batch in flight.

 Derived rather than chosen. The record has to hold both at once, because a
 batch stays durable while it is on the wire and the map keeps accepting
 observations behind it. Sizing it at the map's bound alone is what makes the
 write fail exactly when there is most to lose.

 It is an entry budget rather than a byte budget on purpose: an entry is a
 closed kind, a key capped at 200 bytes and three integers, so the whole record
 is bounded at roughly a quarter of a megabyte by construction.
 */
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2TelemetryMaximumRecordEntries;
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2TelemetryFlushIntervalMilliseconds;
/** The wire contract caps a coalesced count at this value. */
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2TelemetryMaximumEventCount;
FOUNDATION_EXPORT NSUInteger const QONRemoteConfigV2TelemetryMaximumLogicalKeyBytes;
/**
 How old an event may be before a flush drops it instead of sending it.

 The server refuses anything older than 30 days, and refuses it as a 400 that
 takes the whole batch with it. A restored buffer from a phone that was offline
 for a month would otherwise poison every fresh event it shipped with, so the
 client prunes a day early rather than betting on the two clocks agreeing.
 */
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2TelemetryMaximumEventAgeSeconds;
/** How far into the future an event's timestamp may sit before it is pruned. */
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2TelemetryMaximumClockSkewSeconds;

#pragma mark - Kinds

/**
 The closed event enum of the client-telemetry contract.

 `DecodeFailure` is the only kind that carries a logical key, and it MUST carry
 one: the server rejects the whole batch otherwise. Every other kind describes
 the configuration as a whole, not one of its keys.
 */
typedef NS_ENUM(NSInteger, QONRemoteConfigV2TelemetryKind) {
  QONRemoteConfigV2TelemetryKindDecodeFailure,
  QONRemoteConfigV2TelemetryKindReadBeforeActivate,
  QONRemoteConfigV2TelemetryKindImplicitActivation,
  QONRemoteConfigV2TelemetryKindPreloadFailed,
  QONRemoteConfigV2TelemetryKindPreloadCorrupt,
  QONRemoteConfigV2TelemetryKindActivationPersistenceFailed,
  QONRemoteConfigV2TelemetryKindSnapshotMalformed,
};

/** The snake_case name the gateway accepts, or nil for an unknown kind. */
FOUNDATION_EXPORT NSString *_Nullable QONRemoteConfigV2TelemetryKindWireName(
    QONRemoteConfigV2TelemetryKind kind);

#pragma mark - Model

/**
 One coalesced observation: a kind, an optional logical key, the release it was
 observed against, how many times it happened, and when it last did.

 `count` is occurrences since the last successful flush, not since the process
 started: the server adds it to what it already has, so a re-sent batch would
 double-count and a re-counted one would lose history.
 */
@interface QONRemoteConfigV2TelemetryEvent : NSObject <NSCopying>
@property (nonatomic, assign, readonly) QONRemoteConfigV2TelemetryKind kind;
@property (nonatomic, copy, nullable, readonly) NSString *logicalKey;
/** 0 means "none or unknown", which the contract allows for every kind. */
@property (nonatomic, assign, readonly) int64_t releaseNumber;
@property (nonatomic, assign, readonly) int64_t count;
@property (nonatomic, assign, readonly) int64_t lastOccurredAtSeconds;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(QONRemoteConfigV2TelemetryKind)kind
                            logicalKey:(nullable NSString *)logicalKey
                         releaseNumber:(int64_t)releaseNumber
                                 count:(int64_t)count
                 lastOccurredAtSeconds:(int64_t)lastOccurredAtSeconds
    NS_DESIGNATED_INITIALIZER;
/** Exactly the event object the gateway route accepts, or nil when unencodable. */
- (nullable NSDictionary<NSString *, id> *)JSONObject;
@end

/** The durable telemetry buffer of one identity scope. */
@interface QONRemoteConfigV2TelemetryRecord : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSArray<QONRemoteConfigV2TelemetryEvent *> *events;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithEvents:(NSArray<QONRemoteConfigV2TelemetryEvent *> *)events
    NS_DESIGNATED_INITIALIZER;
@end

#pragma mark - Seams

@protocol QONRemoteConfigV2TelemetryStoring <NSObject>
- (nullable QONRemoteConfigV2TelemetryRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)storeRecord:(QONRemoteConfigV2TelemetryRecord *)record
           forScope:(QONRemoteConfigV2Scope *)scope;
- (void)removeRecordForScope:(QONRemoteConfigV2Scope *)scope;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2TelemetryResponse) {
  /** The gateway accepted the batch (`204`, and any other `2xx`). */
  QONRemoteConfigV2TelemetryResponseDelivered,
  /** Retrying can only repeat the same answer — the batch is dropped unsent. */
  QONRemoteConfigV2TelemetryResponsePermanent,
  /** A transport fault or a `429`/`5xx`: worth one more bounded attempt. */
  QONRemoteConfigV2TelemetryResponseRetryable,
  /**
   The transport no longer addresses the identity the batch was collected for.
   No request was made, so it costs no retry budget and the events stay durable
   for the next binding.
   */
  QONRemoteConfigV2TelemetryResponseNotAddressable,
};

typedef void (^QONRemoteConfigV2TelemetryCompletion)(QONRemoteConfigV2TelemetryResponse response);

@protocol QONRemoteConfigV2TelemetryTransporting <NSObject>
- (void)sendTelemetryBatch:(NSArray<QONRemoteConfigV2TelemetryEvent *> *)events
                   forScope:(QONRemoteConfigV2Scope *)scope
                 completion:(QONRemoteConfigV2TelemetryCompletion)completion;
@end

#pragma mark - Sender

/**
 Collects client telemetry and ships it out of band, in aggregate.

 Hard rules, in the order they matter:
 1. **It can never affect the config data path.** `recordKind:...` only hands the
    observation to its own serial queue and returns, so a handler invoked from
    inside a read never blocks, never re-enters the manager and never changes
    what the read returns. Every failure is silent; the only externally visible
    trace of lost telemetry is `droppedEventCount`, a counter rather than a log
    line so a flapping gateway cannot become a log storm.
 2. **It is bounded under repeated failure.** Observations coalesce into a map
    keyed by (kind, logical key): a loop that fails a million times produces ONE
    entry with a count, not a million records. The release number is an
    attribute of the entry rather than part of its identity — the server refuses
    a batch that names the same pair twice — so a release rollover keeps one
    entry, adds the counts and takes the newer release. The map itself is capped
    at `maximumEntries` distinct entries, and a new distinct entry beyond the
    cap is dropped rather than allowed to grow the buffer.
 3. **The buffer is durable.** It is persisted before the first attempt and
    cleared only when delivered, permanently refused or abandoned — so a process
    death between the observation and the flush does not lose it. A batch stays
    in the durable record for as long as it is in flight.
 4. **Retries are bounded.** `maximumAttempts` attempts with exponentially
    growing, jittered delays, then the batch is abandoned and its events are
    counted as dropped. A `400`-family answer skips the ladder entirely: the
    gateway will refuse the same bytes just as firmly next time.

 A flush is due when the map reaches `flushThreshold` distinct entries, when the
 periodic tick fires, or when a fetch succeeded (the one moment the network is
 known to be reachable). At most one flush is ever in flight.

 The whole object only exists when the app configured the experimental Remote
 Config surface, which is what keeps the feature dormant otherwise.
 */
@interface QONRemoteConfigV2TelemetrySender : NSObject
/** Observations that never reached the gateway, ever. Deliberately not a log. */
@property (atomic, assign, readonly) int64_t droppedEventCount;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithTransport:(id<QONRemoteConfigV2TelemetryTransporting>)transport
                                     store:(id<QONRemoteConfigV2TelemetryStoring>)store
                                     clock:(id<QONRemoteConfigV2FetchClock>)clock
                                    random:(id<QONRemoteConfigV2FetchRandom>)random
                                 scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                                     queue:(dispatch_queue_t)queue;
/** Test seam for the bounds and the retry ladder; the shipped path uses the defaults. */
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
                 flushIntervalMilliseconds:(int64_t)flushIntervalMilliseconds
    NS_DESIGNATED_INITIALIZER;

/**
 Binds the sender to `scope` and resumes whatever that scope still owes.

 This is the restart path: the durable buffer is the only thing that survives a
 process, and this is where it is read back. Binding also fences every in-flight
 and scheduled attempt of the previous scope — one identity's session must never
 carry another identity's telemetry.
 */
- (void)bindScope:(nullable QONRemoteConfigV2Scope *)scope;

/**
 Records one observation. Returns immediately, always.

 Safe to call from inside a read: it neither blocks on storage nor calls back
 into anything. `logicalKey` is required for `DecodeFailure` and must be absent
 for every other kind; a violation is dropped rather than sent, because the
 gateway would refuse the whole batch it landed in.
 */
- (void)recordKind:(QONRemoteConfigV2TelemetryKind)kind
        logicalKey:(nullable NSString *)logicalKey
     releaseNumber:(int64_t)releaseNumber;

/** A fetch just succeeded: the network is reachable, so flush opportunistically. */
- (void)noteSuccessfulFetch;

/** Test seam: blocks until every queued unit of telemetry work has run. */
- (void)settleForTesting;
@end

#pragma mark - Durable store

/**
 Durable, per-identity-scope telemetry buffer.

 Mirrors QONRemoteConfigV2ActivationAckStore: the storage key is a salted digest
 of the scope, so neither the project key nor the canonical user id ever lands
 in a storage key.
 */
@interface QONRemoteConfigV2TelemetryStore : NSObject <QONRemoteConfigV2TelemetryStoring>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
    NS_DESIGNATED_INITIALIZER;
+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope;
@end

NS_ASSUME_NONNULL_END
