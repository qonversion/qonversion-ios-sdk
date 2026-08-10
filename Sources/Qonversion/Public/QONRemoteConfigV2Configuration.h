//
//  QONRemoteConfigV2Configuration.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Marks a declaration as part of an experimental Qonversion API surface.

 The full description lives in QONRemoteConfigFetchResult.h. The guard is
 repeated here, idempotently, so this header can be imported on its own without
 dragging in the fetch-result surface it does not otherwise depend on.
 */
#ifndef QON_EXPERIMENTAL
#define QON_EXPERIMENTAL
#endif

/**
 Enables the experimental fetch/activate Remote Config surface.

 The surface is dormant unless an instance of this class is handed to
 `QONConfiguration.setRemoteConfigV2Configuration:`: without it the SDK builds
 no store, opens no connection and contacts no endpoint, while
 `Qonversion.shared().experimentalRemoteConfig` still serves the bundled
 defaults and answers every fetch with `QONRemoteConfigFetchStatusUnavailable`.

 Every initializer validates its arguments and raises
 `NSInvalidArgumentException` on a malformed one. These values are constants of
 the app rather than runtime input, so a mistake is a programming error that
 must surface on the first launch instead of quietly leaving the feature off.

 The configuration carries no project id and no targeting context on purpose.
 The numeric project id is not something a caller knows — the SDK learns it from
 the gateway's session bootstrap — and the targeting context is a per-response
 tag that rotates with the user, so it cannot be pinned ahead of a fetch.

 @see QONRemoteConfigController
 */
NS_SWIFT_NAME(Qonversion.RemoteConfigV2Configuration)
QON_EXPERIMENTAL
@interface QONRemoteConfigV2Configuration : NSObject <NSCopying>

/**
 Base URL of the Remote Config gateway. The SDK appends its own paths, so a bare
 origin is what this is expected to be.
 */
@property (nonatomic, copy, readonly) NSString *baseURL;

/**
 UID of the Remote Config environment to read.

 It is never sent on the wire: it scopes the local storage and the fetch policy,
 and every downloaded envelope is checked against it.
 */
@property (nonatomic, copy, readonly) NSString *environmentUid;

/**
 Overrides the minimum interval between two remote fetches, in milliseconds.

 `0` — the default — means "decide automatically": a debug build fetches without
 throttling, so a freshly published release shows up while you are looking at
 it, and a release build uses the SDK's built-in interval. Any positive value
 replaces both.

 The interval is measured from the last successful fetch, and the forced fetches
 the SDK issues itself — on launch, on identify and on logout — always bypass
 it.
 */
@property (nonatomic, assign, readonly) int64_t minimumFetchIntervalMilliseconds;

- (instancetype)init NS_UNAVAILABLE;

/**
 Configures the surface against the Qonversion production gateway.

 Raises `NSInvalidArgumentException` on a malformed uid. Note that this differs
 from `QONConfiguration.setProxyURL:`, which coerces what it is given — it adds
 a missing scheme and a missing trailing slash. Nothing is coerced here: a
 Remote Config misconfiguration would otherwise read as an app that quietly
 never received a release, which is far harder to notice than a crash on the
 first launch of a debug build.

 @param environmentUid uid of the Remote Config environment to read, 1 to 36
 code points.
 */
- (instancetype)initWithEnvironmentUid:(NSString *)environmentUid;

/**
 Configures the surface against an explicitly addressed gateway.

 Use it only for a proxy or a non-production deployment; the production host is
 already baked into `initWithEnvironmentUid:`.

 Raises `NSInvalidArgumentException` on a malformed url or uid, and coerces
 neither — unlike `QONConfiguration.setProxyURL:`, which adds a missing scheme
 and a missing trailing slash to whatever it is handed. State the url in full.

 @param baseURL absolute http(s) URL of the gateway, e.g. `https://host/`.
 @param environmentUid uid of the Remote Config environment to read, 1 to 36
 code points.
 */
- (instancetype)initWithBaseURL:(NSString *)baseURL
                 environmentUid:(NSString *)environmentUid NS_DESIGNATED_INITIALIZER;

/**
 Overrides the minimum interval between two remote fetches.

 @param minimumFetchIntervalMilliseconds interval in milliseconds, or 0 to let
 the SDK decide. Negative values are refused.
 */
- (void)setMinimumFetchIntervalMilliseconds:(int64_t)minimumFetchIntervalMilliseconds;

- (id)copyWithZone:(NSZone * _Nullable)zone;

@end

NS_ASSUME_NONNULL_END
