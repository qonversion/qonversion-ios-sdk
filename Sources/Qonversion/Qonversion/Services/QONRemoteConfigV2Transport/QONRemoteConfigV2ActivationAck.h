#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2Models.h"

@protocol QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSInteger const QONRemoteConfigV2ActivationAckMaximumAttempts;
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2ActivationAckInitialRetryDelayMilliseconds;
FOUNDATION_EXPORT int64_t const QONRemoteConfigV2ActivationAckMaximumRetryDelayMilliseconds;

#pragma mark - Model

/**
 One activation the app owes the gateway an acknowledgement for.

 `activatedAtSeconds` is stamped when the activation happened, NOT when the ack
 is finally sent: a queued ack can outlive several retries and a process
 restart, and the server is being told when the release started serving.
 */
@interface QONRemoteConfigV2ActivationAck : NSObject <NSCopying>
@property (nonatomic, assign, readonly) int64_t releaseNumber;
@property (nonatomic, assign, readonly) int64_t activatedAtSeconds;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithReleaseNumber:(int64_t)releaseNumber
                            activatedAtSeconds:(int64_t)activatedAtSeconds
    NS_DESIGNATED_INITIALIZER;
@end

/**
 The durable ack bookkeeping of one identity scope.

 `settledReleaseNumber` is what makes the "exactly one ack per (scope, release)"
 promise survive a restart: without it every cold start would re-ack the release
 it activates from persisted state. A release is settled once the gateway either
 accepted the ack or refused it permanently — both are answers, and neither is
 worth asking again.
 */
@interface QONRemoteConfigV2ActivationAckRecord : NSObject <NSCopying>
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2ActivationAck *pending;
@property (nonatomic, assign, readonly) int64_t settledReleaseNumber;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPending:(nullable QONRemoteConfigV2ActivationAck *)pending
                     settledReleaseNumber:(int64_t)settledReleaseNumber
    NS_DESIGNATED_INITIALIZER;
@end

#pragma mark - Seams

@protocol QONRemoteConfigV2ActivationAckStoring <NSObject>
- (nullable QONRemoteConfigV2ActivationAckRecord *)recordForScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)storeRecord:(QONRemoteConfigV2ActivationAckRecord *)record
           forScope:(QONRemoteConfigV2Scope *)scope;
- (void)removeRecordForScope:(QONRemoteConfigV2Scope *)scope;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2AckResponse) {
  /** The gateway accepted the ack (`204`, and any other `2xx`). */
  QONRemoteConfigV2AckResponseDelivered,
  /** Retrying can only repeat the same answer — the release is settled unsent. */
  QONRemoteConfigV2AckResponsePermanent,
  /** A transport fault or a `429`/`5xx`: worth one more bounded attempt. */
  QONRemoteConfigV2AckResponseRetryable,
  /**
   The transport no longer addresses the identity the ack was queued for. No
   request was made, so it costs no retry budget and the queued ack stays
   durable for the next binding.
   */
  QONRemoteConfigV2AckResponseNotAddressable,
};

typedef void (^QONRemoteConfigV2AckCompletion)(QONRemoteConfigV2AckResponse response);

@protocol QONRemoteConfigV2AckTransporting <NSObject>
- (void)sendAck:(QONRemoteConfigV2ActivationAck *)ack
       forScope:(QONRemoteConfigV2Scope *)scope
     completion:(QONRemoteConfigV2AckCompletion)completion;
@end

#pragma mark - Sender

/**
 Reports every activation that made a release serve, exactly once per
 (scope, release).

 Hard rules, in the order they matter:
 1. **It can never affect the config data path.** Nothing here calls back into
    the app, blocks an activation, or feeds the fetch policy. Every failure is
    silent; the only externally visible trace of a lost ack is
    `droppedAckCount`, a counter rather than a log line so a flapping gateway
    cannot turn into a log storm.
 2. **At most one ack is in flight per scope, and the newest activation wins.**
    A later activation supersedes an older queued or in-flight one: the server
    wants to know which release is serving now, and re-sending the intermediate
    ones would be a request storm for no information.
 3. **A queued ack is durable.** It is persisted before the first attempt and
    cleared only when delivered, permanently refused, or superseded — so a
    process death between activation and delivery does not lose it.
 4. **Retries are bounded per process, not per binding.** `maximumAttempts`
    attempts with exponentially growing, jittered delays, then delivery of that
    release is abandoned for the lifetime of the process — a rebind cannot buy
    it another three. The durable record survives the abandonment, so the next
    process start tries once more, and only a newer release re-arms delivery
    inside this one.

 Every public method returns immediately: all state lives on the serial `queue`
 handed in at construction, and that is also where the durable read and write
 happen, so no caller thread — main, the activation path or an HTTP callback
 thread — can ever be parked on storage. The serial queue is likewise what
 orders the durable writes, so there is no separate write stamp.

 The whole object only exists when the app configured the experimental Remote
 Config surface, which is what keeps the feature dormant otherwise.
 */
@interface QONRemoteConfigV2ActivationAckSender : NSObject
/** Acks abandoned without delivery, ever. Deliberately a counter and not a log. */
@property (atomic, assign, readonly) int64_t droppedAckCount;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithTransport:(id<QONRemoteConfigV2AckTransporting>)transport
                                     store:(id<QONRemoteConfigV2ActivationAckStoring>)store
                                     clock:(id<QONRemoteConfigV2FetchClock>)clock
                                    random:(id<QONRemoteConfigV2FetchRandom>)random
                                 scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                                     queue:(dispatch_queue_t)queue;
/** Test seam for the retry ladder; the shipped path uses the defaults. */
- (nullable instancetype)initWithTransport:(id<QONRemoteConfigV2AckTransporting>)transport
                                     store:(id<QONRemoteConfigV2ActivationAckStoring>)store
                                     clock:(id<QONRemoteConfigV2FetchClock>)clock
                                    random:(id<QONRemoteConfigV2FetchRandom>)random
                                 scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                                     queue:(dispatch_queue_t)queue
                           maximumAttempts:(NSInteger)maximumAttempts
             initialRetryDelayMilliseconds:(int64_t)initialRetryDelayMilliseconds
             maximumRetryDelayMilliseconds:(int64_t)maximumRetryDelayMilliseconds
    NS_DESIGNATED_INITIALIZER;

/**
 Binds the sender to `scope` and resumes whatever ack that scope still owes.

 This is the restart path: the durable record is the only thing that survives a
 process, and this is where it is read back. Binding also fences every in-flight
 and scheduled attempt of the previous scope — one identity's session must never
 vouch for another's activation.
 */
- (void)bindScope:(nullable QONRemoteConfigV2Scope *)scope;

/**
 Queues an ack for the release that just became active in `scope`.

 Idempotent by (scope, release): an already settled release and an already
 queued one are both no-ops, so the caller may report the same activation as
 often as it likes — which is how an implicit (read-triggered) activation and
 the explicit `activate` that follows still produce exactly one ack.
 */
- (void)recordActivationForScope:(nullable QONRemoteConfigV2Scope *)scope
                   releaseNumber:(int64_t)releaseNumber;

/** Test seam: blocks until every queued unit of ack work has run. */
- (void)settleForTesting;
@end

#pragma mark - Durable store

/**
 Durable, per-identity-scope ack bookkeeping.

 Mirrors QONRemoteConfigV2GatewaySessionStore: the storage key is a salted
 digest of the scope, so neither the project key nor the canonical user id ever
 lands in a storage key.
 */
@interface QONRemoteConfigV2ActivationAckStore : NSObject <QONRemoteConfigV2ActivationAckStoring>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage
    NS_DESIGNATED_INITIALIZER;
+ (NSString *)storageKeyForScope:(QONRemoteConfigV2Scope *)scope;
@end

NS_ASSUME_NONNULL_END
