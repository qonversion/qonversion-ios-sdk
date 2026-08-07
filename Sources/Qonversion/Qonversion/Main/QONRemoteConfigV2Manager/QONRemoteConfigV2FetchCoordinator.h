#import <Foundation/Foundation.h>
#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigV2Models.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigV2ConditionalRequestValidator : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *strongETag;
@property (nonatomic, copy, readonly) NSString *bodyDigest;
@property (nonatomic, assign, readonly) int64_t headAdmissionOrdinal;
- (nullable instancetype)initWithStrongETag:(NSString *)strongETag
                                  bodyDigest:(NSString *)bodyDigest
                    headAdmissionOrdinal:(int64_t)headAdmissionOrdinal;
@end

@protocol QONRemoteConfigV2FetchCore <NSObject>
- (void)setScope:(nullable QONRemoteConfigV2Scope *)scope;
/** Must not be the read-guarded accessor: the coordinator reads for the SDK. */
- (QONRemoteConfigSnapshot *)unguardedSnapshot;
- (nullable QONRemoteConfigV2AdmissionToken *)beginAdmissionForScope:(QONRemoteConfigV2Scope *)scope
                                                        expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation;
- (QONRemoteConfigV2TransitionStatus)admitBody:(NSData *)body
                                   strongETag:(NSString *)strongETag
                               admissionToken:(QONRemoteConfigV2AdmissionToken *)admissionToken;
- (nullable QONRemoteConfigV2ConditionalRequestValidator *)conditionalRequestValidator;
- (BOOL)isConditionalRequestValidatorCurrent:(QONRemoteConfigV2ConditionalRequestValidator *)validator;
@end

@interface QONRemoteConfigV2Manager (QONRemoteConfigV2FetchCore) <QONRemoteConfigV2FetchCore>
@end

/**
 One scope the coordinator may fetch for.

 The binding carries no context fingerprint, and must not. The fingerprint
 hashes mutable targeting context (app/OS version, locale, purchases,
 properties); it rotates legitimately and MUST NOT be pinned across fetches.
 Identity isolation is the session's job — this binding's scope is what keys
 the session token and the persisted state.
 */
@interface QONRemoteConfigV2FetchBinding : NSObject <NSCopying>
@property (nonatomic, strong, readonly) QONRemoteConfigV2Scope *scope;
@property (nonatomic, assign, readonly) int64_t projectID;
@property (nonatomic, strong, readonly) QONRemoteConfigV2EnvelopeExpectation *expectation;
- (nullable instancetype)initWithScope:(QONRemoteConfigV2Scope *)scope
                             projectID:(int64_t)projectID;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2FetchForceReason) {
  QONRemoteConfigV2FetchForceReasonNone,
  QONRemoteConfigV2FetchForceReasonBuild,
  QONRemoteConfigV2FetchForceReasonIdentify,
  QONRemoteConfigV2FetchForceReasonLogout,
};

@interface QONRemoteConfigV2FetchPolicy : NSObject <NSCopying>
@property (nonatomic, assign, readonly) int64_t minimumFetchIntervalMilliseconds;
@property (nonatomic, strong, nullable, readonly) NSNumber *timeoutMilliseconds;
@property (nonatomic, assign, readonly) int64_t initialBackoffMilliseconds;
@property (nonatomic, assign, readonly) int64_t maximumBackoffMilliseconds;
- (nullable instancetype)initWithMinimumFetchIntervalMilliseconds:(int64_t)minimumFetchIntervalMilliseconds
                                               timeoutMilliseconds:(nullable NSNumber *)timeoutMilliseconds
                                        initialBackoffMilliseconds:(int64_t)initialBackoffMilliseconds
                                        maximumBackoffMilliseconds:(int64_t)maximumBackoffMilliseconds;
@end

@interface QONRemoteConfigV2FetchPolicyState : NSObject <NSCopying>
@property (nonatomic, assign, readonly) int64_t lastSuccessfulFetchAtMilliseconds;
@property (nonatomic, assign, readonly) NSInteger consecutiveRetryableFailures;
@property (nonatomic, assign, readonly) int64_t nextAllowedFetchAtMilliseconds;
- (nullable instancetype)initWithLastSuccessfulFetchAtMilliseconds:(int64_t)lastSuccessfulFetchAtMilliseconds
                                      consecutiveRetryableFailures:(NSInteger)consecutiveRetryableFailures
                                    nextAllowedFetchAtMilliseconds:(int64_t)nextAllowedFetchAtMilliseconds;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2FetchPolicyLoadStatus) {
  QONRemoteConfigV2FetchPolicyLoadStatusFound,
  QONRemoteConfigV2FetchPolicyLoadStatusMissing,
  QONRemoteConfigV2FetchPolicyLoadStatusFailed,
  QONRemoteConfigV2FetchPolicyLoadStatusCorrupt,
};

/** Explicit load outcome so unavailable or corrupt guard state can never fail open as Missing. */
@interface QONRemoteConfigV2FetchPolicyLoadResult : NSObject
@property (nonatomic, assign, readonly) QONRemoteConfigV2FetchPolicyLoadStatus status;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2FetchPolicyState *state;
- (nullable instancetype)initWithStatus:(QONRemoteConfigV2FetchPolicyLoadStatus)status
                                  state:(nullable QONRemoteConfigV2FetchPolicyState *)state;
@end

@interface QONRemoteConfigV2FetchPolicyScope : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *projectKey;
@property (nonatomic, copy, readonly) NSString *environment;
- (nullable instancetype)initWithProjectKey:(NSString *)projectKey environment:(NSString *)environment;
+ (instancetype)scopeFromRemoteConfigScope:(QONRemoteConfigV2Scope *)scope;
@end

@protocol QONRemoteConfigV2FetchPolicyStoring <NSObject>
- (QONRemoteConfigV2FetchPolicyLoadResult *)loadResultForScope:(QONRemoteConfigV2FetchPolicyScope *)scope;
- (BOOL)saveState:(QONRemoteConfigV2FetchPolicyState *)state
          forScope:(QONRemoteConfigV2FetchPolicyScope *)scope;
@end

@protocol QONRemoteConfigV2FetchClock <NSObject>
- (int64_t)nowMilliseconds;
@end

@protocol QONRemoteConfigV2FetchRandom <NSObject>
- (double)nextUnitInterval;
@end

@protocol QONRemoteConfigV2FetchScheduledTask <NSObject>
- (void)cancel;
@end

@protocol QONRemoteConfigV2FetchScheduler <NSObject>
- (id<QONRemoteConfigV2FetchScheduledTask>)scheduleAfterMilliseconds:(int64_t)delay
                                                              action:(dispatch_block_t)action;
@end

@interface QONRemoteConfigV2FetchRequest : NSObject
@property (nonatomic, copy, nullable, readonly) NSString *ifNoneMatch;
- (instancetype)initWithIfNoneMatch:(nullable NSString *)ifNoneMatch;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2FetchResponseKind) {
  QONRemoteConfigV2FetchResponseKindSuccess,
  QONRemoteConfigV2FetchResponseKindNotModified,
  QONRemoteConfigV2FetchResponseKindFailure,
};

@interface QONRemoteConfigV2FetchResponse : NSObject
@property (nonatomic, assign, readonly) QONRemoteConfigV2FetchResponseKind kind;
@property (nonatomic, copy, nullable, readonly) NSData *body;
@property (nonatomic, copy, nullable, readonly) NSString *strongETag;
@property (nonatomic, strong, nullable, readonly) NSNumber *statusCode;
/** Transport-normalized Retry-After delay. The coordinator gives it precedence over jitter. */
@property (nonatomic, strong, nullable, readonly) NSNumber *retryAfterMilliseconds;
+ (instancetype)successWithBody:(NSData *)body strongETag:(NSString *)strongETag;
+ (instancetype)notModifiedWithStrongETag:(nullable NSString *)strongETag;
+ (instancetype)failureWithStatusCode:(nullable NSNumber *)statusCode
                retryAfterMilliseconds:(nullable NSNumber *)retryAfterMilliseconds;
@end

typedef void (^QONRemoteConfigV2FetchTransportCompletion)(QONRemoteConfigV2FetchResponse *response);

@protocol QONRemoteConfigV2FetchTransport <NSObject>
- (void)fetchRequest:(QONRemoteConfigV2FetchRequest *)request
          completion:(QONRemoteConfigV2FetchTransportCompletion)completion;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2FetchResultKind) {
  QONRemoteConfigV2FetchResultKindFetched,
  QONRemoteConfigV2FetchResultKindNotModified,
  QONRemoteConfigV2FetchResultKindFailed,
  QONRemoteConfigV2FetchResultKindMinimumInterval,
  QONRemoteConfigV2FetchResultKindBackoff,
  QONRemoteConfigV2FetchResultKindTimedOut,
  QONRemoteConfigV2FetchResultKindPolicyPersistenceFailed,
  QONRemoteConfigV2FetchResultKindInvalidNotModified,
  QONRemoteConfigV2FetchResultKindSuperseded,
};

typedef NS_ENUM(NSInteger, QONRemoteConfigV2FetchPolicyFailureReason) {
  QONRemoteConfigV2FetchPolicyFailureReasonSave,
  QONRemoteConfigV2FetchPolicyFailureReasonLoadFailed,
  QONRemoteConfigV2FetchPolicyFailureReasonLoadCorrupt,
};

@interface QONRemoteConfigV2FetchResult : NSObject
@property (nonatomic, assign, readonly) QONRemoteConfigV2FetchResultKind kind;
@property (nonatomic, assign, readonly) QONRemoteConfigV2TransitionStatus transitionStatus;
@property (nonatomic, strong, nullable, readonly) NSNumber *statusCode;
@property (nonatomic, assign, readonly) int64_t nextAllowedAtMilliseconds;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigSnapshot *snapshot;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2FetchResult *underlyingResult;
@property (nonatomic, assign, readonly) QONRemoteConfigV2FetchPolicyFailureReason policyFailureReason;
@end

typedef void (^QONRemoteConfigV2FetchCompletion)(QONRemoteConfigV2FetchResult *result);
typedef void (^QONRemoteConfigV2FetchPolicyPersistenceFailureObserver)(
    QONRemoteConfigV2FetchPolicyScope *scope,
    QONRemoteConfigV2FetchPolicyFailureReason reason);

@interface QONRemoteConfigV2FetchCoordinator : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCore:(id<QONRemoteConfigV2FetchCore>)core
                    transport:(id<QONRemoteConfigV2FetchTransport>)transport
                  policyStore:(id<QONRemoteConfigV2FetchPolicyStoring>)policyStore
                        clock:(id<QONRemoteConfigV2FetchClock>)clock
                       random:(id<QONRemoteConfigV2FetchRandom>)random
                    scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                       policy:(QONRemoteConfigV2FetchPolicy *)policy;
/** Internal deterministic-test seam. callbackExecutor must be serial. */
- (instancetype)initWithCore:(id<QONRemoteConfigV2FetchCore>)core
                    transport:(id<QONRemoteConfigV2FetchTransport>)transport
                  policyStore:(id<QONRemoteConfigV2FetchPolicyStoring>)policyStore
                        clock:(id<QONRemoteConfigV2FetchClock>)clock
                       random:(id<QONRemoteConfigV2FetchRandom>)random
                    scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                       policy:(QONRemoteConfigV2FetchPolicy *)policy
             callbackExecutor:(dispatch_queue_t)callbackExecutor
 policyPersistenceFailureObserver:(nullable QONRemoteConfigV2FetchPolicyPersistenceFailureObserver)observer
    NS_DESIGNATED_INITIALIZER;
- (void)transitionToBinding:(nullable QONRemoteConfigV2FetchBinding *)binding;
- (void)fetchWithForceReason:(QONRemoteConfigV2FetchForceReason)forceReason
                   completion:(QONRemoteConfigV2FetchCompletion)completion;
@end

NS_ASSUME_NONNULL_END
