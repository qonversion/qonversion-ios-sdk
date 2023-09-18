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
                      params:(NSDictionary *)params
                  completion:(QONRateLimiterCompletionHandler _Nonnull)completion {
  NSUInteger hash = [self calculateHashForDictionary:params];
  [self processWithRateLimit:requestType hash:hash completion:completion];
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
  [self removeOutdatedRequests:requestType];

  NSArray<QONRequest *> *requestsPerType = self.requests[@(requestType)];
  if (requestsPerType == nil) {
    return false;
  }

  int matchCount = 0;
  for (NSUInteger i = 0; i < requestsPerType.count && matchCount < self.maxRequestsPerSecond; i++) {
    QONRequest *request = requestsPerType[i];
    if (request.hashValue == hash) {
      matchCount++;
    }
  }

  return matchCount >= self.maxRequestsPerSecond;
}

// MARK: Private

- (void)removeOutdatedRequests:(QONRateLimitedRequestType)requestType {
  NSArray<QONRequest *> *requestsPerType = self.requests[@(requestType)];
  if (requestsPerType == nil) {
    return;
  }

  NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
  NSMutableArray *filteredRequests = [NSMutableArray new];
  for (NSInteger i = requestsPerType.count - 1; i >= 0 && timestamp - requestsPerType[i].timestamp < msInSec; --i) {
    [filteredRequests insertObject:requestsPerType[i] atIndex:0];
  }

  self.requests[@(requestType)] = filteredRequests;
}

- (NSUInteger)calculateHashForDictionary:(NSDictionary *)dict {
  NSUInteger prime = 31;
  NSUInteger result = 1;

  for (NSString *key in dict) {
    id value = dict[key];
    
    NSUInteger keyHash = [key hash];
    NSUInteger valueHash = [self calculateHashForValue:value];
    
    result = prime * result + keyHash;
    result = prime * result + valueHash;
  }
  
  return result;
}

- (NSUInteger)calculateHashForArray:(NSArray *)array {
  NSUInteger prime = 31;
  NSUInteger result = 1;

  for (id value in array) {
    NSUInteger valueHash = [self calculateHashForValue:value];
    result = prime * result + valueHash;
  }

  return result;
}

- (NSUInteger)calculateHashForValue:(id)value {
  NSUInteger valueHash = 0;
  if ([value isKindOfClass:[NSDictionary class]]) {
    valueHash = [self calculateHashForDictionary:value];
  } else if ([value isKindOfClass:[NSArray class]]) {
    valueHash = [self calculateHashForArray:value];
  } else {
    valueHash = [value hash];
  }

  return valueHash;
}

@end
