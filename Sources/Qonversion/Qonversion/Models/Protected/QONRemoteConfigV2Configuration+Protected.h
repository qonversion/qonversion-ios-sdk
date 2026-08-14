//
//  QONRemoteConfigV2Configuration+Protected.h
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigV2Configuration.h"
#import "QONRemoteConfigV2Manager.h"

NS_ASSUME_NONNULL_BEGIN

@interface QONRemoteConfigV2Configuration ()

/**
 The minimum fetch interval the engine must actually be built with, or nil to
 leave the SDK's built-in default in place.

 The resolution lives here rather than at the assembly site because it is the
 configuration's own contract: `minimumFetchIntervalMilliseconds` is documented
 as "0 means decide automatically", and this is that decision. A debug build
 resolves 0 to a real 0 — no throttle at all — while a release build resolves it
 to nil, which the assembly reads as "keep the built-in interval".

 buildMode describes how the *app* was built, exactly like the read guard's, and
 is therefore a caller decision rather than something read off the SDK's own
 compile flavour.
 */
- (nullable NSNumber *)effectiveMinimumFetchIntervalMillisecondsForBuildMode:
    (QONRemoteConfigV2ReadGuardBuildMode)buildMode;

@end

NS_ASSUME_NONNULL_END
