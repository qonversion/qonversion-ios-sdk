//
//  QONRequest.m
//  Qonversion
//
//  Created by Kamo Spertsyan on 13.09.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONRequest.h"

@implementation QONRequest

- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp andHash:(NSUInteger)hashValue {
  self = [super init];

  if (self) {
    _timestamp = timestamp;
    _hashValue = hashValue;
  }

  return self;
}

@end
