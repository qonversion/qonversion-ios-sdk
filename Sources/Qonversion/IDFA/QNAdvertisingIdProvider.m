//
//  QNAdvertisingIdProvider.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 25.08.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNAdvertisingIdProvider.h"

static NSString *const kQNZeroAdvertisingID = @"00000000-0000-0000-0000-000000000000";

@implementation QNAdvertisingIdProvider

+ (nullable NSString *)obtainAdvertisingID {
  NSString *advertiserId = [self advertiserIDWithMaxAttempts:5];
  if (advertiserId.length > 0 && ![advertiserId isEqualToString:kQNZeroAdvertisingID]) {
    return advertiserId;
  }

  return nil;
}

+ (nullable NSString *)advertiserIDWithMaxAttempts:(NSUInteger)maxAttempts {
  Class ASIdentifierManager = NSClassFromString(@"ASIdentifierManager");
  SEL sharedManager = NSSelectorFromString(@"sharedManager");
  SEL advertisingIdentifier = NSSelectorFromString(@"advertisingIdentifier");
  if (ASIdentifierManager && sharedManager && advertisingIdentifier) {
    id (*imp1)(id, SEL) = (id (*)(id, SEL))[ASIdentifierManager methodForSelector:sharedManager];
    id manager = nil;
    NSUUID *adid = nil;
    NSString *identifier = nil;
    if (imp1) {
      manager = imp1(ASIdentifierManager, sharedManager);
    }
    NSUUID* (*imp2)(id, SEL) = (NSUUID* (*)(id, SEL))[manager methodForSelector:advertisingIdentifier];
    if (imp2) {
      adid = imp2(manager, advertisingIdentifier);
    }
    if (adid) {
      identifier = [adid UUIDString];
    }
    if (identifier == nil && maxAttempts > 0) {
      return [self advertiserIDWithMaxAttempts:maxAttempts - 1];
    } else {
      return identifier;
    }
  } else {
    return nil;
  }
}

@end
