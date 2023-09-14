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

typedef NS_ENUM(NSInteger, QONRequestType) {
        QONRequestTypeRemoteConfig = 0,
        QONRequestTypeAttachUserToExperiment = 1,
        QONRequestTypeDetachUserFromExperiment = 2,
        QONRequestTypePurchase = 3,
        QONRequestTypeUserInfo = 4,
        QONRequestTypeAttribution = 5,
        QONRequestTypeGetProperties = 6,
        QONRequestTypeEligibilityForProducts = 7,
        QONRequestTypeIdentify = 8
};

@interface QONRateLimiter : NSObject

- (instancetype)initWithMaxRequestsPerSecond:(int)maxRequestsPerSecond;

- (void)processWithRateLimit:(QONRequestType)requestType
                        hash:(NSUInteger)hash
                  completion:(QONRateLimiterCompletionHandler)completion;

- (void)saveRequest:(QONRequestType)requestType hash:(NSUInteger)hash;

- (BOOL)isRateLimitExceeded:(QONRequestType)requestType hash:(NSUInteger)hash;

@end

#endif /* QNRateLimiter_h */
