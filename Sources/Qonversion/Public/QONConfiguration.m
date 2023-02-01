//
//  QONConfiguration.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import "QONConfiguration.h"
#import "QNAPIConstants.h"

@interface QONConfiguration ()

@property (nonatomic, copy, readwrite) NSString *projectKey;
@property (nonatomic, copy, readwrite) NSString *version;
@property (nonatomic, assign, readwrite) QONLaunchMode launchMode;
@property (nonatomic, assign, readwrite) QONEntitlementsCacheLifetime entitlementsCacheLifetime;
@property (nonatomic, assign, readwrite) BOOL debugMode;
@property (nonatomic, copy, readwrite) NSString *baseURL;
@property (nonatomic, weak, readwrite) id<QONEntitlementsUpdateListener> entitlementsUpdateListener;
@property (nonatomic, weak, readwrite) id<QONPromoPurchasesDelegate> promoPurchasesDelegate;

@end

@implementation QONConfiguration

- (instancetype)initWithProjectKey:(NSString * _Nonnull)projectKey
                        launchMode:(QONLaunchMode)launchMode{
  self = [super init];
  
  if (self) {
    _projectKey = projectKey;
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    _version = bundle.infoDictionary[@"CFBundleShortVersionString"];
    _launchMode = launchMode;
    _environment = QONEnvironmentProduction;
    _entitlementsCacheLifetime = QONEntitlementsCacheLifetimeMonth;
    _baseURL = kAPIBase;
  }
  
  return self;
}

- (void)setEnvironment:(QONEnvironment)environment {
  _environment = environment;
}

- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)entitlementsCacheLifetime {
  _entitlementsCacheLifetime = entitlementsCacheLifetime;
}

- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)entitlementsUpdateListener {
  _entitlementsUpdateListener = entitlementsUpdateListener;
}

- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate {
  _promoPurchasesDelegate = delegate;
}

- (void)setProxyURL:(NSString *)url {
  if (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"]) {
    _baseURL = [NSString stringWithFormat:@"https://%@", url];
  } else {
    _baseURL = url;
  }
  
  if (![_baseURL hasSuffix:@"/"]) {
    _baseURL = [NSString stringWithFormat:@"%@/", _baseURL];
  }
}

- (id)copyWithZone:(NSZone *)zone {
  QONConfiguration *copyConfig = [[QONConfiguration allocWithZone:zone] initWithProjectKey:_projectKey launchMode:_launchMode];
  [copyConfig setEnvironment:_environment];
  [copyConfig setEntitlementsCacheLifetime:_entitlementsCacheLifetime];
  [copyConfig setEntitlementsUpdateListener:_entitlementsUpdateListener];
  
  return copyConfig;
}

@end
