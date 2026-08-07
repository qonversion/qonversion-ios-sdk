//
//  QONRemoteConfigController.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONRemoteConfigFetchResult.h"
#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigUpdate.h"
#import "QONRemoteConfigValue.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^QONRemoteConfigFetchCompletion)(QONRemoteConfigFetchResult *result)
    NS_SWIFT_NAME(Qonversion.RemoteConfigFetchCompletion) QON_EXPERIMENTAL;

typedef void (^QONRemoteConfigUpdateHandler)(QONRemoteConfigUpdate *update)
    NS_SWIFT_NAME(Qonversion.RemoteConfigUpdateHandler) QON_EXPERIMENTAL;

/**
 Experimental fetch/activate Remote Config surface.

 Reach it through `Qonversion.shared().experimentalRemoteConfig`. The object
 always exists, but it stays dormant — no network, no persistence, no identity
 work — until the SDK is explicitly configured for this surface. While dormant,
 reads resolve from the bundled defaults and fetches complete with
 `QONRemoteConfigFetchStatusUnavailable`.

 Model:
 - `fetch` only downloads. It never swaps what the app is reading, unless the
   server marked the release for immediate apply.
 - `activate` publishes the last fetched release as one atomic whole. There is
   no per-key activation: a release is applied completely or not at all.
 - `current` is an immutable snapshot. Holding it gives a consistent view of
   every key even while a newer release is activated on another thread.

 All completions and update handlers run on the main queue.
 */
NS_SWIFT_NAME(Qonversion.RemoteConfigController)
QON_EXPERIMENTAL
@interface QONRemoteConfigController : NSObject

- (instancetype)init NS_UNAVAILABLE;

/** YES once the SDK has been configured for the experimental surface. */
@property (nonatomic, assign, readonly, getter=isConfigured) BOOL configured;

/**
 The immutable configuration the app is reading right now.

 Reading before the first `activate` is a programming error: in a debug build it
 raises an assertion, and in a release build the SDK silently activates the
 persisted release once so the app never sees a partially initialized
 configuration. Call `activate` (or `fetchAndActivate`) during startup.
 */
@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *current;

/**
 Downloads a fresh configuration and gives up waiting after `timeout` seconds.

 A timeout only ends the wait, not the request: the fetch keeps running in the
 background and its release becomes available to a later `activate`. The
 completion always receives the best configuration available at that moment, so
 a read on `result.snapshot` still returns a value together with its source
 (`server`, `cache` or `fallback`).

 Pass a non-positive `timeout` to let the SDK's own fetch policy decide.

 @param timeout    Seconds to wait before completing with the best available
                   configuration.
 @param completion Called on the main queue.
 */
- (void)fetchWithTimeout:(NSTimeInterval)timeout
              completion:(QONRemoteConfigFetchCompletion)completion
    NS_SWIFT_NAME(fetch(timeout:completion:));

/**
 Convenience for `fetchWithTimeout:completion:` with the policy timeout.
 @param completion Called on the main queue.
 */
- (void)fetchWithCompletion:(QONRemoteConfigFetchCompletion)completion
    NS_SWIFT_NAME(fetch(completion:));

/**
 Fetches and then activates in one call. `result.changed` reports whether the
 activation changed what the app reads. A timed-out call activates nothing.
 @param timeout    Seconds to wait before completing with the best available
                   configuration.
 @param completion Called on the main queue.
 */
- (void)fetchAndActivateWithTimeout:(NSTimeInterval)timeout
                         completion:(QONRemoteConfigFetchCompletion)completion
    NS_SWIFT_NAME(fetchAndActivate(timeout:completion:));

/**
 Convenience for `fetchAndActivateWithTimeout:completion:` with the policy timeout.
 @param completion Called on the main queue.
 */
- (void)fetchAndActivateWithCompletion:(QONRemoteConfigFetchCompletion)completion
    NS_SWIFT_NAME(fetchAndActivate(completion:));

/**
 Publishes the last fetched release atomically.
 @return YES when the newly active configuration differs from the previous one.
 */
- (BOOL)activate NS_SWIFT_NAME(activate());

/**
 Typed read from `current` through a caller-supplied decoder.

 The decoder is the validation boundary: when it rejects the served value, the
 read falls back to the previously active value for the same key, and then to
 the bundled default, reporting `cache` or `fallback` accordingly.

 @param key     Context key to read.
 @param decoder Deterministic, side-effect-free JSON decoder.
 @return The resolved value and its source, or nil when the key is unknown
         everywhere or no candidate decodes.
 */
- (nullable QONRemoteConfigValue *)valueForKey:(NSString *)key
                                       decoder:(QONRemoteConfigValueDecoder)decoder
    NS_SWIFT_NAME(value(_:decoder:));

/**
 Untyped read from `current`. It performs no validation, so it never walks down
 to the previously active value: the served value is returned as `server`, and
 the bundled default as `fallback`.
 @param key Context key to read.
 */
- (nullable QONRemoteConfigValue *)rawValueForKey:(NSString *)key
    NS_SWIFT_NAME(rawValue(_:));

/**
 Reads a bundled default straight from the application bundle.

 Synchronous, usable before `activate` and even before the SDK is configured. It
 never consults the network, identity, cache or Documents directory. A JSON null
 is returned as NSNull.
 @param key Context key whose bundled default should be returned.
 */
- (nullable id)bundledFallbackValueForKey:(NSString *)key
    NS_SWIFT_NAME(bundledFallbackValue(_:));

/**
 Exact validated JSON bytes of a bundled default, for callers that decode into
 their own type before the SDK is configured.
 @param key Context key whose bundled default should be returned.
 */
- (nullable NSData *)bundledFallbackRawValueForKey:(NSString *)key
    NS_SWIFT_NAME(bundledFallbackRawValue(_:));

/**
 Observes configuration changes.

 The handler receives the new snapshot, the keys whose effective value changed,
 and the metadata of those keys. It runs on the main queue after an `activate`,
 and also without one when the server marked a release for immediate apply — in
 that case the whole release is swapped atomically, never a single key.

 @param handler Called on the main queue.
 @return An opaque token to pass to `unsubscribe:`.
 */
- (nullable id)subscribeOnConfigUpdate:(QONRemoteConfigUpdateHandler)handler
    NS_SWIFT_NAME(subscribeOnConfigUpdate(_:));

/**
 Stops delivering updates to the handler behind the token.
 @param token Token returned by `subscribeOnConfigUpdate:`.
 */
- (void)unsubscribe:(nullable id)token NS_SWIFT_NAME(unsubscribe(_:));

@end

NS_ASSUME_NONNULL_END
