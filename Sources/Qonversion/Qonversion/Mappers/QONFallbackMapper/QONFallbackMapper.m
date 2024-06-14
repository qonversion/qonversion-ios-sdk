//
//  QONFallbackMapper.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 06.06.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONFallbackMapper.h"
#import "QONFallbackObject.h"
#import "QNMapper.h"
#import "QONRemoteConfigMapper.h"

@interface QONFallbackMapper ()

@property (nonatomic, strong) QNMapper *mapper;
@property (nonatomic, strong) QONRemoteConfigMapper *remoteConfigMapper;

@end

@implementation QONFallbackMapper

- (instancetype)init
{
  self = [super init];
  if (self) {
    _mapper = [QNMapper new];
    _remoteConfigMapper = [QONRemoteConfigMapper new];
  }
  return self;
}

- (QONFallbackObject  * _Nullable)mapFallback:(NSDictionary *)data {
  if (![data isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  QONFallbackObject *fallback = [QONFallbackObject new];
  
  fallback.products = [self.mapper mapProducts:data];
  fallback.offerings = [self.mapper mapOfferings:data];
  fallback.productsEntitlementsRelation = [self.mapper mapProductsEntitlementsRelationships:data];
  
  NSArray *rawRemoteConfigList = data[@"remote_config_list"];
  fallback.remoteConfigList = [self.remoteConfigMapper mapRemoteConfigList:rawRemoteConfigList];
  
  return fallback;
}

@end
