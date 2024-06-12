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
#import "QONFallbacksService.h"
#import "NSError+Sugare.h"
#import "QONFallbackObject.h"

static NSString *const kEmptyContextKey = @"";

@interface QONRemoteConfigManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *loadingStates;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigListRequestData *> *listRequests;
@property (nonatomic, strong) QONFallbackObject *fallbackData;

@end

@implementation QONRemoteConfigManager

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _remoteConfigService = [QONRemoteConfigService new];
    _loadingStates = [NSMutableDictionary new];
    _listRequests = [NSMutableArray new];
    _fallbacksService = [QONFallbacksService new];
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

- (void)userHasBeenChanged {
  self.loadingStates = [NSMutableDictionary new];
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
    return completion(loadingState.loadedConfig, nil);
  }
  
  loadingState.isInProgress = YES;
  
  __block __weak QONRemoteConfigManager *weakSelf = self;
  
  [self.userPropertiesManager forceSendProperties:^{
    [weakSelf.remoteConfigService loadRemoteConfig:contextKey completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
      loadingState.isInProgress = NO;
      if (error) {
        if (error.shouldFireFallback) {
          weakSelf.fallbackData = weakSelf.fallbackData ?: [weakSelf.fallbacksService obtainFallbackData];
          QONRemoteConfig *remoteConfig;
          if (contextKey.length == 0) {
            remoteConfig = [weakSelf.fallbackData.remoteConfigList remoteConfigForEmptyContextKey];
          } else {
            remoteConfig = [weakSelf.fallbackData.remoteConfigList remoteConfigForContextKey:contextKey];
          }

          if (remoteConfig) {
            [weakSelf fireRemoteConfig:remoteConfig contextKey:contextKey loadingState:loadingState error:nil completion:completion];
          } else {
            [weakSelf fireRemoteConfig:nil contextKey:contextKey loadingState:loadingState error:error completion:completion];
            return;
          }
        } else {
          [weakSelf fireRemoteConfig:nil contextKey:contextKey loadingState:loadingState error:error completion:completion];
          return;
        }
      }
      
      [weakSelf fireRemoteConfig:remoteConfig contextKey:contextKey loadingState:loadingState error:nil completion:completion];
    }];
  }];
}

- (void)fireRemoteConfig:(QONRemoteConfig *)remoteConfig contextKey:(NSString *)contextKey loadingState:(QONRemoteConfigLoadingState *)loadingState error:(NSError *)error completion:(QONRemoteConfigCompletionHandler)completion {
  if (error) {
    [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
    completion(nil, error);
  } else {
    loadingState.loadedConfig = remoteConfig;
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
    QONRemoteConfigListCompletionHandler completionWrapper = [weakSelf remoteConfigListCompletionWrapper:completion contextKeys:@[] includeEmptyContextKey:YES];
    [weakSelf.remoteConfigService loadRemoteConfigList:completionWrapper];
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  self.loadingStates[kEmptyContextKey] = nil;
  [self.remoteConfigService attachUserToExperiment:experimentId groupId:groupId completion:completion];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  self.loadingStates[kEmptyContextKey] = nil;
  [self.remoteConfigService detachUserFromExperiment:experimentId completion:completion];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  self.loadingStates[kEmptyContextKey] = nil;
  [self.remoteConfigService attachUserToRemoteConfiguration:remoteConfigurationId completion:completion];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  self.loadingStates[kEmptyContextKey] = nil;
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
  NSString *key = contextKey ?: kEmptyContextKey;
  return self.loadingStates[key];
}

- (QONRemoteConfigListCompletionHandler)remoteConfigListCompletionWrapper:(QONRemoteConfigListCompletionHandler)completion contextKeys:(NSArray *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey {
  NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *localLoadingStates = self.loadingStates;

  __block __weak QONRemoteConfigManager *weakSelf = self;
  
  return ^(QONRemoteConfigList * _Nullable remoteConfigList, NSError * _Nullable error) {
    if (error) {
      weakSelf.fallbackData = weakSelf.fallbackData ?: [weakSelf.fallbacksService obtainFallbackData];
      if (weakSelf.fallbackData.remoteConfigList) {
        if (contextKeys.count == 0) {
          remoteConfigList = weakSelf.fallbackData.remoteConfigList;
        } else {
          NSArray<QONRemoteConfig *> *remoteConfigs = [weakSelf remoteConfigsForContextKeys:contextKeys remoteConfigList:remoteConfigList];
          remoteConfigList.remoteConfigs = remoteConfigs;
        }
      } else {
        completion(nil, error);
        return;
      }
    }
    
    if (remoteConfigList) {
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

- (NSArray<QONRemoteConfig *> *_Nullable)remoteConfigsForContextKeys:(NSArray *)contextKeys remoteConfigList:(QONRemoteConfigList *)remoteConfigList {
  NSMutableArray *remoteConfigs = [NSMutableArray new];
  for (QONRemoteConfig *remoteConfig in remoteConfigList.remoteConfigs) {
    if ([contextKeys containsObject:remoteConfig.source.contextKey]) {
      [remoteConfigs addObject:remoteConfig];
    }
  }
  
  return [remoteConfigs mutableCopy];
}

@end
