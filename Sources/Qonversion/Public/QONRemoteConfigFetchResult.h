//
//  QONRemoteConfigFetchResult.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONRemoteConfigSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Marks a declaration as part of an experimental Qonversion API surface.

 An experimental symbol is shipped for evaluation only. It is disabled unless
 the SDK is explicitly configured for it, and it may change or be removed in
 any release without a deprecation cycle. The marker is intentionally a no-op
 macro so it costs nothing at the call site and stays greppable.
 */
#define QON_EXPERIMENTAL

/**
 Outcome of one Remote Config fetch call.

 `Fetched`, `NotModified` and `Failed` describe what the server leg did.
 `Throttled` means the local fetch policy refused the call (minimum interval or
 failure backoff) without touching the network. `TimedOut` means the caller's
 deadline elapsed first — the request itself keeps running in the background.
 `Unavailable` means the experimental surface is not configured, so no fetch was
 attempted at all.
 */
typedef NS_ENUM(NSInteger, QONRemoteConfigFetchStatus) {
  QONRemoteConfigFetchStatusFetched = 0,
  QONRemoteConfigFetchStatusNotModified = 1,
  QONRemoteConfigFetchStatusThrottled = 2,
  QONRemoteConfigFetchStatusTimedOut = 3,
  QONRemoteConfigFetchStatusFailed = 4,
  QONRemoteConfigFetchStatusUnavailable = 5,
} NS_SWIFT_NAME(Qonversion.RemoteConfigFetchStatus) QON_EXPERIMENTAL;

/** Immutable result handed to a fetch completion. */
NS_SWIFT_NAME(Qonversion.RemoteConfigFetchResult)
QON_EXPERIMENTAL
@interface QONRemoteConfigFetchResult : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, assign, readonly) QONRemoteConfigFetchStatus status;

/**
 Best available configuration at completion time. It is never nil: when nothing
 was ever fetched or activated it resolves from the bundled defaults, so every
 read still returns a value together with its source.
 */
@property (nonatomic, strong, readonly) QONRemoteConfigSnapshot *snapshot;

/** YES when the active configuration changed as part of this call. */
@property (nonatomic, assign, readonly) BOOL changed;

/**
 YES when a newly fetched release is waiting for `activate`. It is always NO for
 a timed-out call, because the fetch that may still admit a release has not
 finished yet.
 */
@property (nonatomic, assign, readonly) BOOL hasPendingActivation;

@end

NS_ASSUME_NONNULL_END
