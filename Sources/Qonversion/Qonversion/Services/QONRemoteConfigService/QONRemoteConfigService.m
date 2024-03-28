//
//  QONRemoteConfigService.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigService.h"
#import "QNAPIClient.h"
#import "QONRemoteConfigMapper.h"
#import "QONRemoteConfig.h"
#import "QONErrors.h"

static NSString *const kNoRemoteConfigurationErrorMessage = @"Remote configuration is not available for the current user or for the provided context key";

@implementation QONRemoteConfigService

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _apiClient = [QNAPIClient shared];
    _mapper = [QONRemoteConfigMapper new];
  }
  
  return self;
}

- (void)loadRemoteConfig:(NSString * _Nullable)contextKey completion:(QONRemoteConfigCompletionHandler)completion {
  __block __weak QONRemoteConfigService *weakSelf = self;
  [self.apiClient loadRemoteConfig:contextKey completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
      return;
    }
    
    QONRemoteConfig *config = [weakSelf.mapper mapRemoteConfig:dict];
    
    if (config.source == nil) {
      NSError *error = [QONErrors errorWithCode:QONErrorRemoteConfigurationNotAvailable message:kNoRemoteConfigurationErrorMessage];
      completion(nil, error);
      return;
    }
    
    completion(config, error);
  }];
}

- (void)loadRemoteConfigList:(QONRemoteConfigListCompletionHandler)completion {
  __block __weak QONRemoteConfigService *weakSelf = self;
  [self.apiClient loadRemoteConfigList:^(NSArray * _Nullable arr, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
      return;
    }
    
    QONRemoteConfigList *configList = [weakSelf.mapper mapRemoteConfigList:arr];
    completion(configList, error);
  }];
}

- (void)loadRemoteConfigList:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion {
  __block __weak QONRemoteConfigService *weakSelf = self;
  [self.apiClient loadRemoteConfigListForContextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey completion:^(NSArray * _Nullable arr, NSError * _Nullable error) {
    if (error) {
      completion(nil, error);
      return;
    }
    
    QONRemoteConfigList *configList = [weakSelf.mapper mapRemoteConfigList:arr];
    completion(configList, error);
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  [self.apiClient attachUserToExperiment:experimentId groupId:groupId completion:^(NSError * _Nullable error) {
    if (error) {
      completion(NO, error);
    } else {
      completion(YES, nil);
    }
  }];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  [self.apiClient detachUserFromExperiment:experimentId completion:^(NSError * _Nullable error) {
    if (error) {
      completion(NO, error);
    } else {
      completion(YES, nil);
    }
  }];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfiguration completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [self.apiClient attachUserToRemoteConfiguration:remoteConfiguration completion:^(NSError * _Nullable error) {
    if (error) {
      completion(NO, error);
    } else {
      completion(YES, nil);
    }
  }];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfiguration completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [self.apiClient detachUserFromRemoteConfiguration:remoteConfiguration completion:^(NSError * _Nullable error) {
    if (error) {
      completion(NO, error);
    } else {
      completion(YES, nil);
    }
  }];
}

@end
