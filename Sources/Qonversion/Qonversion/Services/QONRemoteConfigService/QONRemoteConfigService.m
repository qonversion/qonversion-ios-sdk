//
//  QONRemoteConfigService.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigService.h"
#import "QNAPIClient.h"

@implementation QONRemoteConfigService

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _apiClient = [QNAPIClient shared];
  }
  
  return self;
}

- (void)loadRemoteConfig:(QONRemoteConfigCompletionHandler)completion {
  [self.apiClient loadRemoteConfig:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    NSLog(@"DA");
  }];
}

@end
