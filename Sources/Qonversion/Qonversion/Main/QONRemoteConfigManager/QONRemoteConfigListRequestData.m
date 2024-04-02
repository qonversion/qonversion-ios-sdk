//
//  QONRemoteConfigListRequestData.m
//  Qonversion
//
//  Created by Kamo Spertsyan on 01.04.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigListRequestData.h"

@implementation QONRemoteConfigListRequestData

- (instancetype)initWithCompletion:(QONRemoteConfigListCompletionHandler)completion {
  self = [super init];
  if (self) {
    _completion = completion;
  }
  return self;
}

- (instancetype)initWithContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion {
  self = [super init];
  if (self) {
    _contextKeys = [contextKeys copy];
    _includeEmptyContextKey = includeEmptyContextKey;
    _completion = completion;
  }
  return self;
}

@end
