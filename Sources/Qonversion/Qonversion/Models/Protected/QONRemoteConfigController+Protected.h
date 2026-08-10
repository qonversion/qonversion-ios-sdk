//
//  QONRemoteConfigController+Protected.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigController.h"
#import "QONRemoteConfigFetchResult.h"
#import "QONRemoteConfigV2ActivationAck.h"
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2GatewayTransport.h"
#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigV2Telemetry.h"

@class QONRemoteConfigFallbackStore;
@protocol QNLocalStorage;
@protocol QONRemoteConfigV2ClientContextProviding;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QONRemoteConfigControllerIdentityChange) {
  QONRemoteConfigControllerIdentityChangeBuild,
  QONRemoteConfigControllerIdentityChangeIdentify,
  QONRemoteConfigControllerIdentityChangeLogout,
};

/** Receives every scope transition so a transport can rebind or unbind. */
typedef void (^QONRemoteConfigScopeSink)(QONRemoteConfigV2Scope *_Nullable scope);

@interface QONRemoteConfigFetchResult ()
- (nullable instancetype)initWithStatus:(QONRemoteConfigFetchStatus)status
                               snapshot:(QONRemoteConfigSnapshot *)snapshot
                                changed:(BOOL)changed
                   hasPendingActivation:(BOOL)hasPendingActivation;
@end

/** Store-backed preloader for the manager read guard. Never touches main. */
@interface QONRemoteConfigStorePreloader : NSObject <QONRemoteConfigV2ScopePreloading>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithStore:(QONRemoteConfigV2Store *)store NS_DESIGNATED_INITIALIZER;
@end

/** Wall clock in milliseconds since the epoch. */
@interface QONRemoteConfigSystemClock : NSObject <QONRemoteConfigV2FetchClock>
@end

/** Uniform [0, 1) source for the fetch-policy backoff jitter. */
@interface QONRemoteConfigSystemRandom : NSObject <QONRemoteConfigV2FetchRandom>
@end

/** Cancellable dispatch-timer scheduler. */
@interface QONRemoteConfigDispatchScheduler : NSObject <QONRemoteConfigV2FetchScheduler>
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
@end

@interface QONRemoteConfigController ()

/**
 Builds a dormant controller. Only the bundled-defaults getters and the
 fallback-only `current` work until an engine is installed.
 */
- (nullable instancetype)initWithFallbackStore:(nullable QONRemoteConfigFallbackStore *)fallbackStore
                              callbackExecutor:(dispatch_queue_t)callbackExecutor
    NS_DESIGNATED_INITIALIZER;

/**
 Installs an already-assembled engine. Used by the real configuration path and
 by tests that substitute the transport, scheduler and storage wholesale.
 Installing twice is refused.

 The controller binds every scope itself. Nothing supplies a context
 fingerprint: it is a per-response tag that rotates with the user's targeting
 context, so it neither exists at bootstrap nor holds still between fetches.
 Nothing supplies a numeric project id either — the SDK learns it from the
 gateway's session bootstrap, which is the only party that knows it.
 */
- (BOOL)installEngineWithManager:(QONRemoteConfigV2Manager *)manager
                     coordinator:(QONRemoteConfigV2FetchCoordinator *)coordinator
                      projectKey:(NSString *)projectKey
                     environment:(NSString *)environment
                       scopeSink:(nullable QONRemoteConfigScopeSink)scopeSink
                       scheduler:(id<QONRemoteConfigV2FetchScheduler>)scheduler
                   identityQueue:(dispatch_queue_t)identityQueue;

/**
 Installs the out-of-band activation ack queue.

 Optional by construction: without it the surface simply never acknowledges an
 activation, and nothing else changes. It must be installed before the first
 identity is bound, so the very first activation is already reportable, and it
 is refused afterwards.
 */
- (BOOL)installActivationAckSender:(QONRemoteConfigV2ActivationAckSender *)ackSender;

/**
 Installs the out-of-band client-telemetry queue.

 Optional by construction, exactly like the ack queue: without it the surface
 simply never reports, and nothing else changes. It must be installed before the
 first identity is bound, and it is refused afterwards.
 */
- (BOOL)installTelemetrySender:(QONRemoteConfigV2TelemetrySender *)telemetrySender;

/**
 The three taps that feed the telemetry queue.

 They are built here rather than inline at the assembly site so the mapping from
 SDK-internal events to wire kinds is one implementation, exercised by tests
 that install an engine themselves. Each one only enqueues: they are invoked
 from the app's read path, from a transport callback and from a decoder, none of
 which may be made to wait, re-enter the manager or fail because of telemetry.
 They hold the controller weakly and are harmless before a sender is installed.
 */
- (QONRemoteConfigV2ReadGuardTelemetryHandler)telemetryReadGuardHandler;
- (QONRemoteConfigV2DecodeFailureTelemetryHandler)telemetryDecodeFailureHandler;
- (QONRemoteConfigV2TransportFailureObserver)telemetryTransportFailureObserver;

/**
 Assembles the real engine against the gateway routes and installs it. Nothing
 in the SDK calls this by default: the surface stays dormant until a caller
 supplies a base URL explicitly.

 buildMode is a caller decision on purpose. Deriving it from the SDK's own
 compile flavour would be wrong for a binary distribution, where it describes
 how the SDK was built rather than how the app was.
 */
- (BOOL)configureWithBaseURL:(NSURL *)baseURL
                projectToken:(NSString *)projectToken
                  projectKey:(NSString *)projectKey
                 environment:(NSString *)environment
             canonicalUserID:(nullable NSString *)canonicalUserID
          readGuardBuildMode:(QONRemoteConfigV2ReadGuardBuildMode)buildMode
                localStorage:(id<QNLocalStorage>)localStorage
       clientContextProvider:(id<QONRemoteConfigV2ClientContextProviding>)clientContextProvider;

/**
 Rebinds the surface to another canonical identity. The previous identity's
 configuration stops being readable before this method returns; the rebind and
 the forced fetch finish asynchronously off the main queue. Passing nil leaves
 the surface unbound.
 */
- (void)switchToCanonicalUserID:(nullable NSString *)canonicalUserID
                         change:(QONRemoteConfigControllerIdentityChange)change;

@end

NS_ASSUME_NONNULL_END
