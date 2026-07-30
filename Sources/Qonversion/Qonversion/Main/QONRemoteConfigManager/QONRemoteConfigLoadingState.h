//
//  QONRemoteConfigLoadingState.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 07.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"

@interface QONRemoteConfigLoadingState : NSObject

@property (nonatomic, strong, nullable) QONRemoteConfig *loadedConfig;
@property (nonatomic, strong, nonnull) NSMutableArray<QONRemoteConfigCompletionHandler> *completions;
@property (nonatomic, assign) BOOL isInProgress;

// Last cache generation a superseded in-flight load was re-issued for.
// Defense-in-depth against a concurrent re-entry: the retry count is bounded
// structurally by the per-key isInProgress serialisation (one load, hence one
// superseded response, per invalidation), so this guard is not reachable in
// the current single-threaded flow. Zero means "never": a moved generation
// observed by a response is always >= 1, since the counter only increments
// and the bump precedes the observation.
@property (nonatomic, assign) NSUInteger reissuedForGeneration;

@end
