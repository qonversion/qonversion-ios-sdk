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

@interface QONRemoteConfigManager ()

@property (nonatomic, strong) QONRemoteConfig *remoteConfig;
@property (nonatomic, assign) BOOL isLaunchFinished;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigCompletionHandler> *completions;
@property (nonatomic, assign) BOOL isRequestInProgress;

@end

@implementation QONRemoteConfigManager

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _remoteConfigService = [QONRemoteConfigService new];
    _completions = [NSMutableArray new];
  }
  
  return self;
}

- (void)launchFinished:(BOOL)finished {
  _isLaunchFinished = finished;
  
  if (finished && self.completions.count > 0 && !self.isRequestInProgress) {
    [self obtainRemoteConfig:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {}];
  }
}

- (void)obtainRemoteConfig:(QONRemoteConfigCompletionHandler)completion {
  if (self.remoteConfig) {
    return completion(self.remoteConfig, nil);
  }
  
  if (!self.isLaunchFinished || self.isRequestInProgress) {
    [self.completions addObject:completion];
    
    return;
  }
  
  self.isRequestInProgress = YES;
  __block __weak QONRemoteConfigManager *weakSelf = self;
  [self.remoteConfigService loadRemoteConfig:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    self.isRequestInProgress = NO;
    if (error) {
      [weakSelf executeRemoteConfigCompletions:nil error:error];
      completion(nil, error);
      return;
    }
    
    weakSelf.remoteConfig = remoteConfig;
    [weakSelf executeRemoteConfigCompletions:remoteConfig error:nil];
    completion(remoteConfig, nil);
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  [self.remoteConfigService attachUserToExperiment:experimentId groupId:groupId completion:completion];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  [self.remoteConfigService detachUserFromExperiment:experimentId completion:completion];
}

- (void)executeRemoteConfigCompletions:(QONRemoteConfig *)remoteConfig error:(NSError *)error {
  NSArray *completions = [self.completions copy];
  [self.completions removeAllObjects];
  
  for (QONRemoteConfigCompletionHandler completion in completions) {
    completion(remoteConfig, error);
  }
}

@end
