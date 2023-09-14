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
        QONRateLimitedRequestTypeRemoteConfig = 0,
        QONRateLimitedRequestTypeAttachUserToExperiment = 1,
        QONRateLimitedRequestTypeDetachUserFromExperiment = 2,
        QONRateLimitedRequestTypePurchase = 3,
        QONRateLimitedRequestTypeUserInfo = 4,
        QONRateLimitedRequestTypeAttribution = 5,
        QONRateLimitedRequestTypeGetProperties = 6,
        QONRateLimitedRequestTypeEligibilityForProducts = 7,
        QONRateLimitedRequestTypeIdentify = 8
};

@interface QONRateLimiter : NSObject

- (instancetype)initWithMaxRequestsPerSecond:(int)maxRequestsPerSecond;

- (void)processWithRateLimit:(QONRateLimitedRequestType)requestType
                        hash:(NSUInteger)hash
                  completion:(QONRateLimiterCompletionHandler)completion;

- (void)saveRequest:(QONRateLimitedRequestType)requestType hash:(NSUInteger)hash;

- (BOOL)isRateLimitExceeded:(QONRateLimitedRequestType)requestType hash:(NSUInteger)hash;

@end

#endif /* QNRateLimiter_h */
