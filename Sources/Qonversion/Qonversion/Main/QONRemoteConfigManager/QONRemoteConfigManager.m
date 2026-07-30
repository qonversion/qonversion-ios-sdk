//
//  QONRemoteConfigManager.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigManager.h"
#import "QONRemoteConfigService.h"
#import "QONRemoteConfig.h"
#import "QONRemoteConfigList+Protected.h"
#import "QONExperiment.h"
#import "QNProductCenterManager.h"
#import "QONRemoteConfigLoadingState.h"
#import "QONRemoteConfigListRequestData.h"
#import "QNUserPropertiesManager.h"
#import "QONFallbackService.h"
#import "NSError+Sugare.h"
#import "QONFallbackObject.h"

static NSString *const kEmptyContextKey = @"";

@interface QONRemoteConfigManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *loadingStates;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigListRequestData *> *listRequests;
@property (nonatomic, strong) QONFallbackObject *fallbackData;

// Bumped on every cache invalidation (attach/detach, user change). Loads
// capture it when they start and skip the cache write if it moved — an
// in-flight response evaluated before the invalidating event must not be
// re-cached as fresh. Completions are still delivered either way.
@property (atomic, assign) NSUInteger cacheGeneration;

@end

@implementation QONRemoteConfigManager

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _remoteConfigService = [QONRemoteConfigService new];
    _loadingStates = [NSMutableDictionary new];
    _listRequests = [NSMutableArray new];
    _fallbackService = [QONFallbackService new];
  }
  
  return self;
}

- (void)handlePendingRequests {
  for (NSString *contextKey in self.loadingStates) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState && loadingState.completions.count > 0) {
      [self obtainRemoteConfigWithContextKey:contextKey
                                  completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {}];
    }
  }

  NSArray<QONRemoteConfigListRequestData *> *requestsToSend = [self.listRequests copy];
  [self.listRequests removeAllObjects];

  for (QONRemoteConfigListRequestData *listRequest in requestsToSend) {
    if (listRequest.contextKeys) {
      [self obtainRemoteConfigListWithContextKeys:listRequest.contextKeys includeEmptyContextKey:listRequest.includeEmptyContextKey completion:listRequest.completion];
    } else {
      [self obtainRemoteConfigList:listRequest.completion];
    }
  }
}

- (void)userChangingRequestFailedWithError:(NSError *)error {
  for (NSString *contextKey in self.loadingStates) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState) {
      [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
    }
  }
}

- (void)refreshRemoteConfigs {
  [self invalidateLoadedConfigs];
}

- (void)userHasBeenChanged {
  [self bumpCacheGeneration];
  self.loadingStates = [NSMutableDictionary new];
}

// The increment is a read-modify-write: user changes fire from network
// callback threads while attach/detach invalidations run on the caller
// thread, so it is taken under the lock to avoid losing a bump.
- (void)bumpCacheGeneration {
  @synchronized (self) {
    self.cacheGeneration += 1;
  }
}

- (void)obtainRemoteConfigWithContextKey:(NSString * _Nullable)contextKey completion:(QONRemoteConfigCompletionHandler)completion {
  QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
  if (loadingState == nil) {
    loadingState = [QONRemoteConfigLoadingState new];
    self.loadingStates[contextKey ?: kEmptyContextKey] = loadingState;
  }

  BOOL isUserStable = [self.productCenterManager isUserStable];
  if (!isUserStable || loadingState.isInProgress) {
    [loadingState.completions addObject:completion];
    
    return;
  }
  
  if (loadingState.loadedConfig) {
    // The cached config is served as is, but properties set right before this
    // call must still reach the server — otherwise a cache hit swallows both
    // the property flush and the request.
    [self.userPropertiesManager forceSendProperties:nil];
    return completion(loadingState.loadedConfig, nil);
  }
  
  loadingState.isInProgress = YES;
  NSUInteger generationAtStart = self.cacheGeneration;

  __block __weak QONRemoteConfigManager *weakSelf = self;

  [self.userPropertiesManager forceSendProperties:^{
    [weakSelf.remoteConfigService loadRemoteConfig:contextKey completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
      loadingState.isInProgress = NO;
      if (error) {
        if (error.shouldFireFallback) {
          [weakSelf actualizeFallbackData];
          QONRemoteConfig *remoteConfig;
          if (contextKey.length == 0) {
            remoteConfig = [weakSelf.fallbackData.remoteConfigList remoteConfigForEmptyContextKey];
          } else {
            remoteConfig = [weakSelf.fallbackData.remoteConfigList remoteConfigForContextKey:contextKey];
          }

          if (remoteConfig) {
            [weakSelf fireRemoteConfig:remoteConfig contextKey:contextKey loadingState:loadingState error:nil generation:generationAtStart completion:completion];
          } else {
            [weakSelf fireRemoteConfig:nil contextKey:contextKey loadingState:loadingState error:error generation:generationAtStart completion:completion];
          }
        } else {
          [weakSelf fireRemoteConfig:nil contextKey:contextKey loadingState:loadingState error:error generation:generationAtStart completion:completion];
        }
      } else {
        [weakSelf fireRemoteConfig:remoteConfig contextKey:contextKey loadingState:loadingState error:nil generation:generationAtStart completion:completion];
      }
    }];
  }];
}

- (void)fireRemoteConfig:(QONRemoteConfig *)remoteConfig contextKey:(NSString *)contextKey loadingState:(QONRemoteConfigLoadingState *)loadingState error:(NSError *)error generation:(NSUInteger)generation completion:(QONRemoteConfigCompletionHandler)completion {
  if (error) {
    [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
    completion(nil, error);
  } else {
    if (generation == self.cacheGeneration) {
      // Cache only when no invalidation happened while the load was in flight —
      // a pre-attach evaluation must not be re-cached as fresh. The response is
      // still delivered below either way.
      loadingState.loadedConfig = remoteConfig;
    }
    [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:remoteConfig error:nil];
    completion(remoteConfig, nil);
  }
}

- (void)obtainRemoteConfigListWithContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion {
  NSMutableArray *allKeys = [contextKeys mutableCopy];
  if (includeEmptyContextKey) {
    [allKeys addObject:kEmptyContextKey];
  }
  NSMutableArray<QONRemoteConfig *> *configs = [NSMutableArray new];
  for (NSString *contextKey in allKeys) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState && loadingState.loadedConfig) {
      [configs addObject:loadingState.loadedConfig];
    } else {
      break;
    }
  }

  if (configs.count == allKeys.count) {
    // Same as the single-key cache hit: serve the cached list, but flush
    // pending properties so they are not swallowed by the hit. Gated on user
    // stability (parity with the single-key path, which checks stability before
    // its cache hit) so the flush cannot POST mid-identify to a switching uid.
    if ([self.productCenterManager isUserStable]) {
      [self.userPropertiesManager forceSendProperties:nil];
    }
    QONRemoteConfigList *remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:configs];
    return completion(remoteConfigList, nil);
  }

  BOOL isUserStable = [self.productCenterManager isUserStable];
  if (!isUserStable) {
    QONRemoteConfigListRequestData *requestData = [[QONRemoteConfigListRequestData alloc] initWithContextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey completion:completion];
    [self.listRequests addObject:requestData];
    
    return;
  }
  
  __block __weak QONRemoteConfigManager *weakSelf = self;
  
  [self.userPropertiesManager forceSendProperties:^{
    QONRemoteConfigListCompletionHandler completionWrapper = [weakSelf remoteConfigListCompletionWrapper:completion contextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey];
    [weakSelf.remoteConfigService loadRemoteConfigList:contextKeys includeEmptyContextKey:includeEmptyContextKey completion:completionWrapper];
  }];
}

- (void)obtainRemoteConfigList:(QONRemoteConfigListCompletionHandler)completion {
  BOOL isUserStable = [self.productCenterManager isUserStable];
  if (!isUserStable) {
    QONRemoteConfigListRequestData *requestData = [[QONRemoteConfigListRequestData alloc] initWithCompletion:completion];
    [self.listRequests addObject:requestData];
    
    return;
  }
  
  __block __weak QONRemoteConfigManager *weakSelf = self;
  
  [self.userPropertiesManager forceSendProperties:^{
    QONRemoteConfigListCompletionHandler completionWrapper = [weakSelf remoteConfigListCompletionWrapper:completion contextKeys:nil includeEmptyContextKey:YES];
    [weakSelf.remoteConfigService loadRemoteConfigList:completionWrapper];
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  [self invalidateLoadedConfigs];
  [self.remoteConfigService attachUserToExperiment:experimentId groupId:groupId completion:completion];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  [self invalidateLoadedConfigs];
  [self.remoteConfigService detachUserFromExperiment:experimentId completion:completion];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [self invalidateLoadedConfigs];
  [self.remoteConfigService attachUserToRemoteConfiguration:remoteConfigurationId completion:completion];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [self invalidateLoadedConfigs];
  [self.remoteConfigService detachUserFromRemoteConfiguration:remoteConfigurationId completion:completion];
}

// An attach/detach is addressed by experiment/configuration id, and the SDK
// does not know which context key that entity serves — drop every cached
// config, not just the empty-key one, or configs under named context keys stay
// stale until the process restarts. Loading states themselves are kept so
// pending completions survive. The generation bump also stops in-flight loads
// from re-caching a pre-attach response.
- (void)invalidateLoadedConfigs {
  [self bumpCacheGeneration];
  for (QONRemoteConfigLoadingState *loadingState in self.loadingStates.allValues) {
    loadingState.loadedConfig = nil;
  }
}

- (void)executeRemoteConfigCompletionsWithContextKey:(NSString *)contextKey remoteConfig:(QONRemoteConfig *)remoteConfig error:(NSError *)error {
  QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
  if (loadingState) {
    NSArray *completions = [loadingState.completions copy];
    [loadingState.completions removeAllObjects];
    
    for (QONRemoteConfigCompletionHandler completion in completions) {
      completion(remoteConfig, error);
    }
  }
}

- (QONRemoteConfigLoadingState *)loadingStateForContextKey:(NSString *)contextKey {
  NSString *key = contextKey ?: kEmptyContextKey;
  return self.loadingStates[key];
}

- (QONRemoteConfigListCompletionHandler)remoteConfigListCompletionWrapper:(QONRemoteConfigListCompletionHandler)completion contextKeys:(NSArray *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey {
  NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *localLoadingStates = self.loadingStates;
  NSUInteger generationAtStart = self.cacheGeneration;

  __block __weak QONRemoteConfigManager *weakSelf = self;

  return ^(QONRemoteConfigList * _Nullable remoteConfigList, NSError * _Nullable error) {
    if (error) {
      [weakSelf actualizeFallbackData];
      if (weakSelf.fallbackData.remoteConfigList) {
        if (contextKeys) {
          NSArray<QONRemoteConfig *> *remoteConfigs = [weakSelf remoteConfigsForContextKeys:contextKeys remoteConfigList:remoteConfigList includeEmptyContextKey:includeEmptyContextKey];
          remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:remoteConfigs];
        } else {
          remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:weakSelf.fallbackData.remoteConfigList.remoteConfigs];
        }
      } else {
        completion(nil, error);
        return;
      }
    }

    if (remoteConfigList && generationAtStart == weakSelf.cacheGeneration) {
      // Cache only when no invalidation happened while the list load was in
      // flight — pre-attach evaluations must not be re-cached as fresh. The
      // list is still delivered below either way.
      for (QONRemoteConfig *remoteConfig in remoteConfigList.remoteConfigs) {
        NSString *contextKey = remoteConfig.source.contextKey ?: kEmptyContextKey;
        QONRemoteConfigLoadingState *loadingState = localLoadingStates[contextKey] ?: [QONRemoteConfigLoadingState new];
        loadingState.loadedConfig = remoteConfig;
        localLoadingStates[contextKey] = loadingState;
      }
    }

    completion(remoteConfigList, nil);
  };
}

- (NSArray<QONRemoteConfig *> *_Nullable)remoteConfigsForContextKeys:(NSArray *)contextKeys remoteConfigList:(QONRemoteConfigList *)remoteConfigList includeEmptyContextKey:(BOOL)includeEmptyContextKey {
  if (contextKeys.count == 0 && !includeEmptyContextKey) {
    return @[];
  }
  
  NSMutableArray *remoteConfigs = [NSMutableArray new];
  for (QONRemoteConfig *remoteConfig in remoteConfigList.remoteConfigs) {
    BOOL shouldAddCurrentRemoteConfigWithEmptyContextKey = includeEmptyContextKey && remoteConfig.source.contextKey.length == 0;
    if (shouldAddCurrentRemoteConfigWithEmptyContextKey || [contextKeys containsObject:remoteConfig.source.contextKey]) {
      [remoteConfigs addObject:remoteConfig];
    }
  }
  
  return [remoteConfigs copy];
}

- (void)actualizeFallbackData {
  self.fallbackData = self.fallbackData ?: [self.fallbackService obtainFallbackData];
}

@end
