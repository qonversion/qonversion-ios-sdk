//
//  QONRemoteConfigFallbackStore.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

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

@end

NS_ASSUME_NONNULL_END
