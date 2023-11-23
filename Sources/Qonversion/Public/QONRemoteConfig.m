//
//  QONRemoteConfig.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 24.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfig.h"

@implementation QONRemoteConfig

- (instancetype)initWithPayload:(NSDictionary *)payload experiment:(QONExperiment *)experiment source:(QONRemoteConfigurationSource *)source {
  self = [super init];
  
  if (self) {
    _payload = payload;
    _experiment = experiment;
    _source = source;
  }
  
  return self;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  [description appendFormat:@"payload=%@\n", self.payload];
  [description appendFormat:@"experiment=%@\n", self.experiment];
  [description appendFormat:@"source=%@\n", self.source];
  [description appendString:@">"];
  
  return [description copy];
}

@end
