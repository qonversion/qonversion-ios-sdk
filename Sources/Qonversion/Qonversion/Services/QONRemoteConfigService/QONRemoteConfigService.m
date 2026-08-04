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
#import "QONRemoteConfigList.h"
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

    // A successful response without a source is the API's authoritative
    // "there is no applicable configuration" sentinel. Preserve that public
    // contract before strict shape/context validation so callers can
    // distinguish removal from a transient or malformed response.
    if ([dict isKindOfClass:[NSDictionary class]]) {
      id sourceObject = dict[@"source"];
      if (!sourceObject || sourceObject == [NSNull null]) {
        completion(nil, [QONErrors errorWithCode:QONErrorCodeRemoteConfigurationNotAvailable
                                         message:kNoRemoteConfigurationErrorMessage]);
        return;
      }
    }
    
    QONRemoteConfig *config = [weakSelf.mapper mapRemoteConfig:dict];
    
    if (![weakSelf isValidRemoteConfig:config] ||
        ![[weakSelf normalizedContextKey:config.source.contextKey]
            isEqualToString:[weakSelf normalizedContextKey:contextKey]]) {
      completion(nil, [QONErrors internalErrorWithCode:QONErrorCodeResponseParsingFailed]);
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
    if (![weakSelf isValidRemoteConfigList:configList expectedCount:arr.count allowedContextKeys:nil]) {
      completion(nil, [QONErrors internalErrorWithCode:QONErrorCodeResponseParsingFailed]);
      return;
    }
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
    NSMutableSet<NSString *> *allowedContextKeys = [NSMutableSet new];
    for (NSString *contextKey in contextKeys) {
      [allowedContextKeys addObject:[weakSelf normalizedContextKey:contextKey]];
    }
    if (includeEmptyContextKey) {
      [allowedContextKeys addObject:@""];
    }
    if (![weakSelf isValidRemoteConfigList:configList
                             expectedCount:arr.count
                        allowedContextKeys:allowedContextKeys]) {
      completion(nil, [QONErrors internalErrorWithCode:QONErrorCodeResponseParsingFailed]);
      return;
    }
    completion(configList, error);
  }];
}

- (NSString *)normalizedContextKey:(NSString *)contextKey {
  return contextKey ?: @"";
}

- (BOOL)isValidRemoteConfig:(QONRemoteConfig *)config {
  id sourceIdentifier = config.source.identifier;
  id sourceName = config.source.name;
  id sourceContextKey = config.source.contextKey;
  if (!config || !config.source ||
      ![sourceIdentifier isKindOfClass:[NSString class]] || [sourceIdentifier length] == 0 ||
      ![sourceName isKindOfClass:[NSString class]] ||
      (sourceContextKey && ![sourceContextKey isKindOfClass:[NSString class]]) ||
      (config.payload && ![config.payload isKindOfClass:[NSDictionary class]]) ||
      config.source.type == QONRemoteConfigurationSourceTypeUnknown ||
      config.source.assignmentType == QONRemoteConfigurationAssignmentTypeUnknown) {
    return NO;
  }
  if (config.experiment) {
    id experimentIdentifier = config.experiment.identifier;
    id experimentName = config.experiment.name;
    id groupIdentifier = config.experiment.group.identifier;
    id groupName = config.experiment.group.name;
    if (!config.experiment.group ||
        ![experimentIdentifier isKindOfClass:[NSString class]] || [experimentIdentifier length] == 0 ||
        ![experimentName isKindOfClass:[NSString class]] ||
        ![groupIdentifier isKindOfClass:[NSString class]] || [groupIdentifier length] == 0 ||
        ![groupName isKindOfClass:[NSString class]] ||
        config.experiment.group.type == QONExperimentGroupTypeUnknown) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)isValidRemoteConfigList:(QONRemoteConfigList *)configList
                  expectedCount:(NSUInteger)expectedCount
             allowedContextKeys:(NSSet<NSString *> *)allowedContextKeys {
  if (!configList || configList.remoteConfigs.count != expectedCount) {
    return NO;
  }
  NSMutableSet<NSString *> *seenContextKeys = [NSMutableSet new];
  for (QONRemoteConfig *config in configList.remoteConfigs) {
    if (![self isValidRemoteConfig:config]) {
      return NO;
    }
    NSString *contextKey = [self normalizedContextKey:config.source.contextKey];
    if ([seenContextKeys containsObject:contextKey] ||
        (allowedContextKeys && ![allowedContextKeys containsObject:contextKey])) {
      return NO;
    }
    [seenContextKeys addObject:contextKey];
  }
  return YES;
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
