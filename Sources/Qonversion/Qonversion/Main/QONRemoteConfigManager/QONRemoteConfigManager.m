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

@interface QONRemoteConfigManager ()

@property (nonatomic, strong) QONRemoteConfig *remoteConfig;

@end

@implementation QONRemoteConfigManager

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _remoteConfigService = [QONRemoteConfigService new];
  }
  
  return self;
}

- (void)remoteConfig:(QONRemoteConfigCompletionHandler)completion {
  if (self.remoteConfig) {
    return completion(self.remoteConfig, nil);
  }
  
  [self.remoteConfigService loadRemoteConfig:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    
  }];
}

@end
