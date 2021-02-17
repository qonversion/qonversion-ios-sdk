//
//  QNExperimentGroup.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 15.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNExperimentGroup.h"

@implementation QNExperimentGroup

- (instancetype)initWithType:(QNExperimentGroupType)type {
  self = [super init];
  
  if (self) {
    _type = type;
  }
  
  return self;
}

@end
