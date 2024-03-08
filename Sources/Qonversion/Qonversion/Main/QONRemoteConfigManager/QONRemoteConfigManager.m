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
#import "QONExperiment.h"
#import "QNProductCenterManager.h"
#import "QONRemoteConfigLoadingState.h"

static NSString *const kDefaultLoadingStateKey = @"";

@interface QONRemoteConfigManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *loadingStates;

@end

@implementation QONRemoteConfigManager

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _remoteConfigService = [QONRemoteConfigService new];
    _loadingStates = [NSMutableDictionary new];
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
}

- (void)userChangingRequestFailedWithError:(NSError *)error {
  for (NSString *contextKey in self.loadingStates) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState) {
      [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
    }
  }
}

- (void)userHasBeenChanged {
  self.loadingStates = [NSMutableDictionary new];
}

- (void)obtainRemoteConfigWithContextKey:(NSString * _Nullable)contextKey completion:(QONRemoteConfigCompletionHandler)completion {
  BOOL isUserStable = [self.productCenterManager isUserStable];
  QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
  if (loadingState == nil) {
    loadingState = [QONRemoteConfigLoadingState new];
    self.loadingStates[contextKey ?: kDefaultLoadingStateKey] = loadingState;
  }

  if (!isUserStable || loadingState.isInProgress) {
    [loadingState.completions addObject:completion];
    
    return;
  }
  
  if (loadingState.loadedConfig) {
    return completion(loadingState.loadedConfig, nil);
  }
  
  loadingState.isInProgress = YES;
  __block __weak QONRemoteConfigManager *weakSelf = self;
  [self.remoteConfigService loadRemoteConfig:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    loadingState.isInProgress = NO;
    if (error) {
      [weakSelf executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
      completion(nil, error);
      return;
    }
    
    loadingState.loadedConfig = remoteConfig;
    [weakSelf executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:remoteConfig error:nil];
    completion(remoteConfig, nil);
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  self.loadingStates[kDefaultLoadingStateKey] = nil;
  [self.remoteConfigService attachUserToExperiment:experimentId groupId:groupId completion:completion];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  self.loadingStates[kDefaultLoadingStateKey] = nil;
  [self.remoteConfigService detachUserFromExperiment:experimentId completion:completion];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  self.loadingStates[kDefaultLoadingStateKey] = nil;
  [self.remoteConfigService attachUserToRemoteConfiguration:remoteConfigurationId completion:completion];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  self.loadingStates[kDefaultLoadingStateKey] = nil;
  [self.remoteConfigService detachUserFromRemoteConfiguration:remoteConfigurationId completion:completion];
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
  NSString *key = contextKey ?: kDefaultLoadingStateKey;
  return self.loadingStates[key];
}

@end
