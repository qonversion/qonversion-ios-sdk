//
//  QNExperimentInfo.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNExperimentInfo.h"

@implementation QNExperimentInfo

- (instancetype)initWithIdentifier:(NSString *)identifier group:(QNExperimentGroup *)group {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _group = group;
  }
  
  return self;
}

@end
