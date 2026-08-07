//
//  QONRemoteConfigFetchResult.m
//  Qonversion
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigFetchResult.h"
#import "QONRemoteConfigController+Protected.h"

@implementation QONRemoteConfigFetchResult

- (instancetype)initWithStatus:(QONRemoteConfigFetchStatus)status
                      snapshot:(QONRemoteConfigSnapshot *)snapshot
                       changed:(BOOL)changed
          hasPendingActivation:(BOOL)hasPendingActivation {
  if (!snapshot) return nil;
  self = [super init];
  if (self) {
    _status = status;
    _snapshot = snapshot;
    _changed = changed;
    _hasPendingActivation = hasPendingActivation;
  }
  return self;
}

@end
