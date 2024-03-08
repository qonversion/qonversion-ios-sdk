//
//  QONRemoteConfigLoadingState.m
//  Qonversion
//
//  Created by Kamo Spertsyan on 07.03.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigLoadingState.h"

@implementation QONRemoteConfigLoadingState

- (instancetype)init
{
  self = [super init];
  if (self) {
    _completions = [NSMutableArray new];
  }
  return self;
}

@end
