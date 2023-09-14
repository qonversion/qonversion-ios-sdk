//
//  QONRateLimiter.m
//  Qonversion
//
//  Created by Kamo Spertsyan on 13.09.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QONRateLimiter.h"
#import "QONRequest.h"
#import "QONErrors.h"

static NSInteger const msInSec = 1000;

@interface QONRateLimiter()

@property (nonatomic) int maxRequestsPerSecond;
@property (nonatomic, copy) NSMutableDictionary<NSNumber *, NSMutableArray<QONRequest *> *> *requests;

@end

@implementation QONRateLimiter

- (instancetype)initWithMaxRequestsPerSecond:(int)maxRequestsPerSecond {
  self = super.init;
  if (self) {
    _maxRequestsPerSecond = maxRequestsPerSecond;
    _requests = [NSMutableDictionary new];
  }

  return self;
}

- (void)processWithRateLimit:(QONRateLimitedRequestType)requestType
                        hash:(NSUInteger)hash
                  completion:(QONRateLimiterCompletionHandler)completion {
  if ([self isRateLimitExceeded:requestType hash:hash]) {
    completion([QONErrors errorWithCode:QONAPIErrorRateLimitExceeded]);
  } else {
    [self saveRequest:requestType hash:hash];
    completion(nil);
  }
}

- (void)saveRequest:(QONRateLimitedRequestType)requestType hash:(NSUInteger)hash {
  NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;

  if (self.requests[@(requestType)] == nil) {
    self.requests[@(requestType)] = [NSMutableArray new];
  }

  QONRequest *request = [[QONRequest alloc] initWithTimestamp:timestamp andHash:hash];
  [self.requests[@(requestType)] addObject:request];
}

- (BOOL)isRateLimitExceeded:(QONRateLimitedRequestType)requestType hash:(NSUInteger)hash {
  NSArray<QONRequest *> *requestsPerType = self.requests[@(requestType)];
  if (requestsPerType == nil) {
    return false;
  }

  NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  int matchCount = 0;
  for (NSInteger i = requestsPerType.count - 1; i >= 0; --i) {
    QONRequest *request = requestsPerType[i];
    if (timestamp - request.timestamp >= msInSec || matchCount >= self.maxRequestsPerSecond) {
      break;
    }

    if (request.hashValue == hash) {
      matchCount++;
    }
  }

  return matchCount >= self.maxRequestsPerSecond;
}

@end
