//
//  QONRemoteConfigController+Protected.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigController.h"
#import "QONRemoteConfigFetchResult.h"
#import "QONRemoteConfigV2FetchCoordinator.h"
#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigV2Models.h"

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
