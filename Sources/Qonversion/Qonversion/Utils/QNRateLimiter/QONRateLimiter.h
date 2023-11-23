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
  QONRateLimitedRequestTypeAttachUserToExperiment = 2,
  QONRateLimitedRequestTypeDetachUserFromExperiment = 3,
  QONRateLimitedRequestTypePurchase = 4,
  QONRateLimitedRequestTypeUserInfo = 5,
  QONRateLimitedRequestTypeAttribution = 6,
  QONRateLimitedRequestTypeGetProperties = 7,
  QONRateLimitedRequestTypeEligibilityForProducts = 8,
  QONRateLimitedRequestTypeIdentify = 9,
  QONRateLimitedRequestTypeAttachUserToRemoteConfiguration = 10,
  QONRateLimitedRequestTypeDetachUserFromRemoteConfiguration = 11,
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
