//
//  QONConfiguration.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import "QONConfiguration.h"

@interface QONConfiguration ()

@property (nonatomic, copy, readwrite) NSString *projectKey;
@property (nonatomic, assign, readwrite) QONLaunchMode launchMode;
@property (nonatomic, assign, readwrite) QNEntitlementsCacheLifetime *entitlementsCacheLifetime;
@property (nonatomic, assign, readwrite) BOOL debugMode;
@property (nonatomic, weak, readwrite) id<QONEntitlementsUpdateListener> entitlementsUpdateListener;

@end

@implementation QONConfiguration

- (instancetype)initWithProjectKey:(NSString * _Nonnull)projectKey
                        launchMode:(QONLaunchMode)launchMode{
  self = [super init];
  
  if (self) {
    _projectKey = projectKey;
    _launchMode = launchMode;
    _environment = QONEnvironmentProduction;
  }
  
  return self;
}

- (void)setEnvironment:(QONEnvironment)environment {
  _environment = environment;
}

- (void)setEntitlementsCacheLifetime:(QNEntitlementsCacheLifetime *)entitlementsCacheLifetime {
  _entitlementsCacheLifetime = entitlementsCacheLifetime;
}

- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)entitlementsUpdateListener {
  _entitlementsUpdateListener = entitlementsUpdateListener;
}

- (id)copyWithZone:(NSZone *)zone {
  QONConfiguration *copyConfig = [[QONConfiguration allocWithZone:zone] initWithProjectKey:_projectKey launchMode:_launchMode];
  
  return copyConfig;
}

@end