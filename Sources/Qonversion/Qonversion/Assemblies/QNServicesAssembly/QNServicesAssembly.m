//
//  QNServicesAssembly.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 19.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNServicesAssembly.h"
#import "QNUserInfoService.h"
#import "QNUserDefaultsStorage.h"
#import "QNInternalConstants.h"
#import "QNIdentityManager.h"
#import "QNIdentityService.h"
#import "QNAPIClient.h"
#import "QNUserInfoMapper.h"

@interface QNServicesAssembly ()

@property (nonatomic, strong) NSUserDefaults *customUserDefaults;

@end

@implementation QNServicesAssembly

- (instancetype)initWithCustomUserDefaults:(NSUserDefaults *)userDefaults {
  self = [super init];
  
  if (self) {
    _customUserDefaults = userDefaults;
  }
  
  return self;
}

- (id<QNUserInfoServiceInterface>)userInfoService {
  QNUserInfoService *service = [QNUserInfoService new];
  service.localStorage = [self localStorage];
  service.apiClient = [QNAPIClient shared];
  service.mapper = [self userInfoMapper];
  
  return service;
}

- (id<QNIdentityManagerInterface>)identityManager {
  QNIdentityManager *manager = [QNIdentityManager new];
  manager.identityService = [self identityService];
  manager.userInfoService = [self userInfoService];
  
  return manager;
}

- (id<QNIdentityServiceInterface>)identityService {
  QNIdentityService *service = [QNIdentityService new];
  service.apiClient = [QNAPIClient shared];
  
  return service;
}

- (id<QNLocalStorage>)localStorage {
  QNUserDefaultsStorage *storage = [QNUserDefaultsStorage new];
  storage.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kMainUserDefaultsSuiteName];
  storage.customUserDefaults = self.customUserDefaults;
  
  return storage;
}

- (id<QNUserInfoMapperInterface>)userInfoMapper {
  QNUserInfoMapper *mapper = [QNUserInfoMapper new];
  
  return mapper;
}

@end
