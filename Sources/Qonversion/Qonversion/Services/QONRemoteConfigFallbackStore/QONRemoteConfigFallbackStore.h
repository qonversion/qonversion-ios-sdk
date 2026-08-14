//
//  QONRemoteConfigFallbackStore.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class QONRemoteConfigV2Release;

NS_ASSUME_NONNULL_BEGIN

/**
 A process-local, immutable view of the generated Remote Config defaults in a
 specific bundle. This store never consults Documents, persistence, identity,
 or the network.
 */
@interface QONRemoteConfigFallbackStore : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithBundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;

/**
 Returns the JSON value for a context key, or nil when the key is absent or the
 complete artifact fails validation. A JSON null is returned as NSNull.
 */
- (nullable id)valueForContextKey:(nullable NSString *)contextKey;

/** Exact validated JSON bytes retained for deterministic typed decoding. */
- (nullable NSData *)rawValueForContextKey:(nullable NSString *)contextKey;

/** Whole bundled release; nil when the complete artifact is absent or invalid. */
- (nullable QONRemoteConfigV2Release *)remoteConfigV2FallbackRelease;

@property (nonatomic, assign, readonly) int64_t projectID;
@property (nonatomic, copy, nullable, readonly) NSString *environmentUID;

@end

NS_ASSUME_NONNULL_END
