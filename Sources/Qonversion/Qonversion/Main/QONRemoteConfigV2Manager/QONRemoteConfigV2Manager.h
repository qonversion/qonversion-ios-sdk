#import <Foundation/Foundation.h>
#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigUpdate.h"

@class QONRemoteConfigV2AdmissionToken, QONRemoteConfigV2EnvelopeExpectation;
@class QONRemoteConfigV2Release, QONRemoteConfigV2Scope, QONRemoteConfigV2State;
@class QONRemoteConfigV2Store;
@protocol QONRemoteConfigV2EnvelopeDecoding;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONRemoteConfigV2UpdateObserver)(QONRemoteConfigUpdate *update);

FOUNDATION_EXPORT NSString *const QONRemoteConfigV2ReadBeforeActivateAssertionMessage;

typedef NS_ENUM(NSInteger, QONRemoteConfigV2ReadGuardBuildMode) {
  QONRemoteConfigV2ReadGuardBuildModeDebug,
  QONRemoteConfigV2ReadGuardBuildModeRelease,
};

typedef NS_ENUM(NSInteger, QONRemoteConfigV2ReadGuardPreloadStatus) {
  QONRemoteConfigV2ReadGuardPreloadStatusFound,
  QONRemoteConfigV2ReadGuardPreloadStatusMissing,
  QONRemoteConfigV2ReadGuardPreloadStatusFailed,
  QONRemoteConfigV2ReadGuardPreloadStatusCorrupt,
  QONRemoteConfigV2ReadGuardPreloadStatusPersistenceFailed,
};

typedef NS_ENUM(NSInteger, QONRemoteConfigV2ReadGuardTelemetryEvent) {
  QONRemoteConfigV2ReadGuardTelemetryEventReadBeforeActivate,
  QONRemoteConfigV2ReadGuardTelemetryEventImplicitActivation,
  QONRemoteConfigV2ReadGuardTelemetryEventPreloadAbsent,
  QONRemoteConfigV2ReadGuardTelemetryEventPreloadFailed,
  QONRemoteConfigV2ReadGuardTelemetryEventPreloadCorrupt,
  QONRemoteConfigV2ReadGuardTelemetryEventPreparedActivationPersistenceFailed,
};

typedef void (^QONRemoteConfigV2ReadGuardAssertionHandler)(NSString *message);
typedef void (^QONRemoteConfigV2ReadGuardTelemetryHandler)(
    QONRemoteConfigV2ReadGuardTelemetryEvent event);

/** Immutable output of an injected, off-main persistent-state preload. */
@interface QONRemoteConfigV2ReadGuardPreloadResult : NSObject
@property (nonatomic, assign, readonly) QONRemoteConfigV2ReadGuardPreloadStatus status;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigV2State *state;
- (nullable instancetype)initWithStatus:(QONRemoteConfigV2ReadGuardPreloadStatus)status
                                  state:(nullable QONRemoteConfigV2State *)state;
@end

@protocol QONRemoteConfigV2ScopePreloading <NSObject>
- (QONRemoteConfigV2ReadGuardPreloadResult *)preloadResultForScope:
    (QONRemoteConfigV2Scope *)scope;
@end

typedef NS_ENUM(NSInteger, QONRemoteConfigV2TransitionStatus) {
  QONRemoteConfigV2TransitionStatusAccepted,
  QONRemoteConfigV2TransitionStatusActivated,
  QONRemoteConfigV2TransitionStatusIgnored,
  QONRemoteConfigV2TransitionStatusPersistenceFailed,
  QONRemoteConfigV2TransitionStatusRejected,
  QONRemoteConfigV2TransitionStatusUnchanged,
};

/** Opaque, single-request capability. Tokens are valid only for the manager that issued them. */
@interface QONRemoteConfigV2AdmissionToken : NSObject
- (instancetype)init NS_UNAVAILABLE;
@end

@interface QONRemoteConfigV2Manager : NSObject

@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *currentSnapshot;
/**
 The same snapshot without touching the read guard.

 Only for SDK-internal delivery, where the SDK — not the app — is the one
 reading. It never asserts and never consumes the one-time implicit activation,
 so it must not be used to answer a public `current` read.
 */
@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *unguardedSnapshot;
@property (nonatomic, strong, nullable, readonly) QONRemoteConfigSnapshot *lastFetchedSnapshot;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment;
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder;
/** Internal deterministic-test seam. callbackExecutor must be serial. */
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder
                callbackExecutor:(dispatch_queue_t)callbackExecutor NS_DESIGNATED_INITIALIZER;
/** Internal dark-launch seam. Existing initializers leave the guard disabled. */
- (instancetype)initWithStore:(QONRemoteConfigV2Store *)store
               fallbackRelease:(nullable QONRemoteConfigV2Release *)fallbackRelease
             fallbackProjectKey:(nullable NSString *)fallbackProjectKey
            fallbackEnvironment:(nullable NSString *)fallbackEnvironment
                 envelopeDecoder:(id<QONRemoteConfigV2EnvelopeDecoding>)envelopeDecoder
                callbackExecutor:(dispatch_queue_t)callbackExecutor
              readGuardBuildMode:(QONRemoteConfigV2ReadGuardBuildMode)buildMode
                assertionHandler:(nullable QONRemoteConfigV2ReadGuardAssertionHandler)assertionHandler
                telemetryHandler:(nullable QONRemoteConfigV2ReadGuardTelemetryHandler)telemetryHandler
                  scopePreloader:(id<QONRemoteConfigV2ScopePreloading>)scopePreloader;
/**
 Performs all persistent read and durable prepared-activation work synchronously.
 The SDK bootstrap must call it off main before setScope/readiness.
 */
- (QONRemoteConfigV2ReadGuardPreloadStatus)preloadScopeForReadGuard:
    (QONRemoteConfigV2Scope *)scope;
/**
 Changes current scope and generation synchronously on the state queue without
 waiting for the callback executor. Queued or not-yet-claimed old-generation
 callbacks are cancelled. A callback atomically claimed before this boundary
 may finish after the method returns. No observer runs under an SDK lock.
 */
- (void)setScope:(nullable QONRemoteConfigV2Scope *)scope;
/**
 The expectation states only what a caller can actually know: the project and
 the environment. Its `contextFingerprint` is normally nil, because nothing on
 the device can know it — see QONRemoteConfigV2EnvelopeExpectation.
 */
- (nullable QONRemoteConfigV2AdmissionToken *)beginAdmissionForScope:(QONRemoteConfigV2Scope *)scope
                                                        expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation;
- (QONRemoteConfigV2TransitionStatus)admitBody:(NSData *)body
                                   strongETag:(NSString *)strongETag
                               admissionToken:(QONRemoteConfigV2AdmissionToken *)admissionToken;
- (void)acceptFetchedRelease:(QONRemoteConfigV2Release *)release
                     forScope:(QONRemoteConfigV2Scope *)scope;
- (BOOL)activate;
/** Observer callbacks use the serial main executor by default. */
- (id)addUpdateObserver:(QONRemoteConfigV2UpdateObserver)observer;
- (void)removeUpdateObserver:(id)token;

@end

NS_ASSUME_NONNULL_END
