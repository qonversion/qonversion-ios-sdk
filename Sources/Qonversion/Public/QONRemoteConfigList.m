//
//  QONRemoteConfigList.m
//  Qonversion
//
//  Created by Kamo Spertsyan on 27.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigList.h"

@implementation QONRemoteConfigList

- (instancetype)initWithRemoteConfigs:(NSArray *)remoteConfigs {
  self = [super init];
  
  if (self) {
    _remoteConfigs = [remoteConfigs copy];
  }
  
  return self;
}

- (QONRemoteConfig *_Nullable)remoteConfigForContextKey:(NSString *)key {
  return [self findRemoteConfigForContextKey:key];
}

- (QONRemoteConfig *_Nullable)remoteConfigForEmptyContextKey {
  return [self findRemoteConfigForContextKey:nil];
}

- (QONRemoteConfig *)findRemoteConfigForContextKey:(NSString *_Nullable)key {
  for (QONRemoteConfig *config in self.remoteConfigs) {
    if ((key == nil && config.source.contextKey == nil) || [config.source.contextKey isEqualToString:key]) {
      return config;
    }
  }
  return nil;
}

@end
