//
//  QONRateLimiter.h
//  Qonversion
//
//  Created by Kamo Spertsyan on 13.09.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#ifndef QNRateLimiter_h
#define QNRateLimiter_h

#import <Foundation/Foundation.h>

typedef void (^QONRateLimiterCompletionHandler)(NSError * _Nullable rateLimitError);

typedef NS_ENUM(NSInteger, QONRateLimitedRequestType) {
  QONRateLimitedRequestTypeInit = 0,
  QONRateLimitedRequestTypeRemoteConfig = 1,
  QONRateLimitedRequestTypeRemoteConfigList = 2,
  QONRateLimitedRequestTypeAttachUserToExperiment = 3,
  QONRateLimitedRequestTypeDetachUserFromExperiment = 4,
  QONRateLimitedRequestTypePurchase = 5,
  QONRateLimitedRequestTypeUserInfo = 6,
  QONRateLimitedRequestTypeAttribution = 7,
  QONRateLimitedRequestTypeGetProperties = 8,
  QONRateLimitedRequestTypeEligibilityForProducts = 9,
  QONRateLimitedRequestTypeIdentify = 10,
  QONRateLimitedRequestTypeAttachUserToRemoteConfiguration = 11,
  QONRateLimitedRequestTypeDetachUserFromRemoteConfiguration = 12,
};

@interface QONRateLimiter : NSObject

- (instancetype _Nullable)initWithMaxRequestsPerSecond:(NSUInteger)maxRequestsPerSecond;

- (void)validateRateLimit:(QONRateLimitedRequestType)requestType
                   params:(NSDictionary * _Nonnull)params
               completion:(QONRateLimiterCompletionHandler _Nonnull)completion;

- (void)validateRateLimit:(QONRateLimitedRequestType)requestType
                     hash:(NSUInteger)hash
               completion:(QONRateLimiterCompletionHandler _Nonnull)completion;

- (void)saveRequest:(QONRateLimitedRequestType)requestType hash:(NSUInteger)hash;

- (BOOL)isRateLimitExceeded:(QONRateLimitedRequestType)requestType hash:(NSUInteger)hash;

@end

#endif /* QNRateLimiter_h */
